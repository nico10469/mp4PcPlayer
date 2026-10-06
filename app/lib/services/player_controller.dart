import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'library_store.dart';

/// Il timer di spegnimento: a un'ora precisa o alla fine del brano in riproduzione.
class SleepTimer {
  const SleepTimer.at(DateTime this.at) : endOfTrack = false;
  const SleepTimer.endOfTrack() : at = null, endOfTrack = true;

  final DateTime? at;
  final bool endOfTrack;
}

/// Riproduzione dei brani locali, con coda, riproduzione in background (notifica e schermata
/// di blocco su Android e iPhone), ripresa dal punto in cui si era rimasti, timer di
/// spegnimento, dissolvenza tra i brani ed equalizzatore (Android).
class PlayerController extends ChangeNotifier {
  PlayerController(this.library, {SharedPreferences? prefs, bool? effects})
    : _prefs = prefs,
      _effects = effects ?? (!kIsWeb && Platform.isAndroid) {
    library.addListener(_onLibraryChanged);
    _fade = Duration(seconds: prefs?.getInt(_fadeKey) ?? 0);
  }

  final LibraryStore library;
  final SharedPreferences? _prefs;
  final bool _effects;
  AudioPlayer? _player;
  List<Track> _queue = const [];
  int? _index;

  static const _queueKey = 'player_queue';
  static const _indexKey = 'player_index';
  static const _positionKey = 'player_position';
  static const _shuffleKey = 'player_shuffle';
  static const _loopKey = 'player_loop';
  static const _fadeKey = 'player_fade';
  static const _eqOnKey = 'eq_enabled';
  static const _eqGainsKey = 'eq_gains';

  /// Per contare ogni ascolto una volta sola: (coda, posizione) dell'ultimo brano contato.
  int _generation = 0;
  (int, int)? _counted;

  /// L'equalizzatore di Android (null altrove: su Windows e iPhone non c'è).
  AndroidEqualizer? _equalizer;
  AndroidEqualizer? get equalizer {
    if (!_effects) return null;
    player; // l'equalizzatore nasce insieme al player
    return _equalizer;
  }

  /// Il player si crea al primo uso, così l'app parte anche dove l'audio non è disponibile (test).
  AudioPlayer get player {
    final existing = _player;
    if (existing != null) return existing;
    final eq = _effects ? AndroidEqualizer() : null;
    _equalizer = eq;
    final p = AudioPlayer(audioPipeline: eq == null ? null : AudioPipeline(androidAudioEffects: [eq]));
    p.currentIndexStream.listen((i) {
      final changed = i != _index;
      _index = i;
      _countPlay();
      if (changed) {
        _onTrackChanged();
        _saveQueue();
      }
      notifyListeners();
    });
    p.playerStateStream.listen((s) {
      _countPlay();
      // In pausa si salva subito il punto, così riaprendo l'app si riparte da lì.
      if (!s.playing) _savePosition(force: true);
      notifyListeners();
    });
    p.positionStream.listen(_onPosition);
    if (eq != null) unawaited(_restoreEqualizer(eq));
    return _player = p;
  }

  Track? get current {
    final i = _index;
    if (i == null || i >= _queue.length) return null;
    return _fresh(_queue[i]);
  }

  /// Rilegge il brano dalla libreria, così le modifiche ai metadati si vedono subito.
  Track _fresh(Track t) => library.byId(t.id) ?? t;

  bool get isPlaying => _player?.playing ?? false;

  /// Un ascolto conta quando il brano comincia davvero a suonare.
  void _countPlay() {
    final i = _index;
    if (!isPlaying || i == null || i >= _queue.length || _counted == (_generation, i)) return;
    _counted = (_generation, i);
    library.recordPlay(_queue[i].id).catchError((_) {});
  }

  /// Il brano per il player, con titolo, artista e copertina per la notifica e la schermata di blocco.
  AudioSource _source(Track t) {
    final cover = library.coverFile(t);
    return AudioSource.file(
      library.audioFile(t).path,
      tag: MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        artUri: cover == null ? null : Uri.file(cover.path),
      ),
    );
  }

  Future<void> playQueue(List<Track> tracks, {int start = 0, bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    _index = start;
    _generation++;
    _fadingIn = false;
    notifyListeners();
    await player.setShuffleModeEnabled(shuffle);
    await player.setAudioSources([for (final t in _queue) _source(t)], initialIndex: start);
    if (shuffle) await player.shuffle();
    _saveQueue();
    await player.play();
  }

  /// Mette [track] subito dopo il brano in riproduzione (o lo avvia, se non suona niente).
  Future<void> playNext(Track track) async {
    final i = _index;
    if (i == null || _queue.isEmpty) return playQueue([track]);
    _queue = [..._queue.take(i + 1), track, ..._queue.skip(i + 1)];
    await player.insertAudioSource(i + 1, _source(track));
    _saveQueue();
    notifyListeners();
  }

  /// Aggiunge [track] in fondo alla coda.
  Future<void> addToQueue(Track track) async {
    if (_queue.isEmpty) return playQueue([track]);
    _queue = [..._queue, track];
    await player.addAudioSource(_source(track));
    _saveQueue();
    notifyListeners();
  }

  // ---- Coda ----

  /// I brani della coda nell'ordine in cui sono stati messi (con "Casuale" l'ordine di ascolto
  /// è diverso: vedi [playOrder]).
  List<Track> get queue => [for (final t in _queue) _fresh(t)];

  int? get currentIndex => _index;

  bool get shuffleEnabled => _player?.shuffleModeEnabled ?? false;

  /// Le posizioni della coda nell'ordine in cui si ascolteranno.
  List<int> get playOrder {
    final p = _player;
    if (p == null || _queue.isEmpty) return [for (var i = 0; i < _queue.length; i++) i];
    final order = p.effectiveIndices;
    return order.length == _queue.length ? order : [for (var i = 0; i < _queue.length; i++) i];
  }

  /// Le posizioni dei brani che verranno dopo quello in riproduzione, nell'ordine di ascolto.
  List<int> get upNext {
    final order = playOrder;
    final at = order.indexOf(_index ?? -1);
    return at < 0 ? order : order.sublist(at + 1);
  }

  /// Salta al brano in posizione [index] della coda.
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _fadingIn = false;
    await player.seek(Duration.zero, index: index);
    if (!isPlaying) await player.play();
  }

  /// Toglie dalla coda il brano in posizione [index] (non quello che sta suonando).
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length || index == _index) return;
    _queue = [..._queue]..removeAt(index);
    // L'indice del brano corrente lo aggiorna il player (currentIndexStream).
    await player.removeAudioSourceAt(index);
    _saveQueue();
    notifyListeners();
  }

  /// Sposta un brano della coda da [from] a [to] (posizioni nell'ordine della coda).
  Future<void> moveInQueue(int from, int to) async {
    if (from == to || from < 0 || to < 0 || from >= _queue.length || to >= _queue.length) return;
    final list = [..._queue];
    list.insert(to, list.removeAt(from));
    _queue = list;
    await player.moveAudioSource(from, to);
    _saveQueue();
    notifyListeners();
  }

  /// Svuota la coda tranne il brano in riproduzione.
  Future<void> clearUpNext() async {
    final i = _index;
    if (i == null) return;
    for (final j in [...upNext]..sort((a, b) => b.compareTo(a))) {
      await removeFromQueue(j);
    }
  }

  Future<void> togglePlay() async {
    if (isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> next() {
    _fadingIn = false;
    return player.seekToNext();
  }

  Future<void> previous() async {
    _fadingIn = false;
    // Come nelle app di musica: dopo i primi secondi "indietro" riavvia il brano.
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> setShuffle(bool on) async {
    if (on) await player.shuffle();
    await player.setShuffleModeEnabled(on);
    await _prefs?.setBool(_shuffleKey, on);
    notifyListeners();
  }

  Future<void> setLoopMode(LoopMode mode) async {
    await player.setLoopMode(mode);
    await _prefs?.setString(_loopKey, mode.name);
  }

  // ---- Ripresa all'avvio ----

  int _savedPositionMs = -1;

  void _saveQueue() {
    final prefs = _prefs;
    if (prefs == null) return;
    unawaited(prefs.setStringList(_queueKey, [for (final t in _queue) t.id]));
    unawaited(prefs.setInt(_indexKey, _index ?? 0));
    _savePosition(force: true);
  }

  void _savePosition({bool force = false}) {
    final prefs = _prefs;
    final p = _player;
    if (prefs == null || p == null || _queue.isEmpty) return;
    final ms = p.position.inMilliseconds;
    // Mentre suona si salva ogni 5 secondi, non a ogni aggiornamento.
    if (!force && (ms - _savedPositionMs).abs() < 5000) return;
    _savedPositionMs = ms;
    unawaited(prefs.setInt(_positionKey, ms));
  }

  /// Rimette la coda dell'ultima volta, ferma sul brano e sul punto in cui era (senza suonare).
  Future<void> restore() async {
    final prefs = _prefs;
    if (prefs == null || _queue.isNotEmpty) return;
    final ids = prefs.getStringList(_queueKey) ?? const [];
    if (ids.isEmpty) return;
    final saved = prefs.getInt(_indexKey) ?? 0;
    final currentId = ids[saved.clamp(0, ids.length - 1)];
    // I brani eliminati nel frattempo restano fuori.
    final tracks = [for (final id in ids) ?library.byId(id)];
    if (tracks.isEmpty) return;
    var start = tracks.indexWhere((t) => t.id == currentId);
    // Il brano di prima è stato eliminato: si riparte dall'inizio della coda.
    final position = start < 0 ? Duration.zero : Duration(milliseconds: prefs.getInt(_positionKey) ?? 0);
    if (start < 0) start = 0;

    _queue = tracks;
    _index = start;
    _generation++;
    final loop = LoopMode.values.where((m) => m.name == prefs.getString(_loopKey)).firstOrNull ?? LoopMode.off;
    await player.setLoopMode(loop);
    await player.setAudioSources([for (final t in _queue) _source(t)], initialIndex: start, initialPosition: position);
    if (prefs.getBool(_shuffleKey) ?? false) {
      await player.shuffle();
      await player.setShuffleModeEnabled(true);
    }
    notifyListeners();
  }

  // ---- Timer di spegnimento ----

  SleepTimer? _sleep;
  Timer? _sleepTimer;

  SleepTimer? get sleepTimer => _sleep;

  /// Ferma la musica dopo [after], oppure alla fine del brano con [endOfTrack]. null = spento.
  void setSleepTimer({Duration? after, bool endOfTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (endOfTrack) {
      _sleep = const SleepTimer.endOfTrack();
    } else if (after != null) {
      _sleep = SleepTimer.at(DateTime.now().add(after));
      _sleepTimer = Timer(after, _sleepNow);
    } else {
      _sleep = null;
    }
    notifyListeners();
  }

  void _sleepNow() {
    _sleep = null;
    _sleepTimer = null;
    unawaited(_player?.pause());
    notifyListeners();
  }

  void _onTrackChanged() {
    // "Alla fine del brano": il brano è finito ed è partito il successivo.
    if (_sleep?.endOfTrack ?? false) {
      _sleepNow();
      unawaited(_player?.seek(Duration.zero));
    }
  }

  // ---- Dissolvenza ----

  Duration _fade = Duration.zero;
  double _volume = 1;
  double _fadeFactor = 1;

  /// Dopo una dissolvenza in uscita il brano seguente entra piano.
  bool _fadingIn = false;

  /// Quanto dura la dissolvenza tra un brano e l'altro (zero = nessuna).
  Duration get fade => _fade;

  Future<void> setFade(Duration fade) async {
    _fade = fade;
    await _prefs?.setInt(_fadeKey, fade.inSeconds);
    if (fade == Duration.zero) _applyVolume(1);
    notifyListeners();
  }

  /// Il volume scelto dall'utente (la dissolvenza lo abbassa solo per qualche secondo).
  double get volume => _volume;

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 1).toDouble();
    await player.setVolume(_volume * _fadeFactor);
    notifyListeners();
  }

  void _applyVolume(double factor) {
    if ((factor - _fadeFactor).abs() < 0.02 && factor != 1 && factor != 0) return;
    _fadeFactor = factor;
    unawaited(_player?.setVolume(_volume * factor));
  }

  void _onPosition(Duration pos) {
    _savePosition();
    final p = _player;
    if (p == null) return;
    final fade = _fade;
    if (fade == Duration.zero || !p.playing) return;
    final fadeMs = fade.inMilliseconds;
    var factor = 1.0;

    // In uscita: gli ultimi secondi del brano, se dopo ne viene un altro.
    final total = p.duration;
    final willContinue = p.hasNext || p.loopMode == LoopMode.all;
    if (total != null && willContinue && p.loopMode != LoopMode.one && !(_sleep?.endOfTrack ?? false)) {
      final left = (total - pos).inMilliseconds;
      if (left < fadeMs) {
        factor = math.max(0, left / fadeMs);
        _fadingIn = true;
      }
    }
    // In entrata: i primi secondi del brano che segue una dissolvenza.
    if (_fadingIn && (total == null || (total - pos).inMilliseconds >= fadeMs)) {
      final ms = pos.inMilliseconds;
      if (ms < fadeMs) {
        factor = math.min(factor, ms / fadeMs);
      } else {
        _fadingIn = false;
      }
    }
    _applyVolume(factor);
  }

  // ---- Equalizzatore (solo Android) ----

  bool _eqEnabled = false;
  bool get equalizerEnabled => _eqEnabled;

  Future<void> _restoreEqualizer(AndroidEqualizer eq) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      _eqEnabled = prefs.getBool(_eqOnKey) ?? false;
      await eq.setEnabled(_eqEnabled);
      final gains = prefs.getStringList(_eqGainsKey);
      if (gains == null) return;
      final params = await eq.parameters;
      for (final (i, band) in params.bands.indexed) {
        if (i < gains.length) await band.setGain(double.tryParse(gains[i]) ?? 0);
      }
    } catch (_) {
      // Equalizzatore non disponibile su questo telefono: si ascolta senza.
    }
  }

  Future<void> setEqualizerEnabled(bool on) async {
    final eq = equalizer;
    if (eq == null) return;
    _eqEnabled = on;
    await eq.setEnabled(on);
    await _prefs?.setBool(_eqOnKey, on);
    notifyListeners();
  }

  /// Salva il guadagno di ogni banda (lo chiama la schermata dell'equalizzatore).
  Future<void> saveEqualizerGains(List<double> gains) async {
    await _prefs?.setStringList(_eqGainsKey, [for (final g in gains) g.toStringAsFixed(2)]);
  }

  void _onLibraryChanged() {
    // Se il brano in riproduzione viene eliminato, ferma tutto.
    final i = _index;
    final c = i == null || i >= _queue.length ? null : _queue[i];
    if (c != null && !library.contains(c.id)) {
      _player?.stop();
      _queue = const [];
      _index = null;
      _saveQueue();
      unawaited(_prefs?.remove(_queueKey));
      notifyListeners();
    } else if (c != null) {
      // Metadati modificati: aggiorna il player.
      notifyListeners();
    }
  }

  @override
  void dispose() {
    library.removeListener(_onLibraryChanged);
    _sleepTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }
}
