import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'library_store.dart';

/// Riproduzione dei brani locali, con coda.
class PlayerController extends ChangeNotifier {
  PlayerController(this.library) {
    library.addListener(_onLibraryChanged);
  }

  final LibraryStore library;
  AudioPlayer? _player;
  List<Track> _queue = const [];
  int? _index;

  /// Per contare ogni ascolto una volta sola: (coda, posizione) dell'ultimo brano contato.
  int _generation = 0;
  (int, int)? _counted;

  /// Il player si crea al primo uso, così l'app parte anche dove l'audio non è disponibile (test).
  AudioPlayer get player {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    p.currentIndexStream.listen((i) {
      _index = i;
      _countPlay();
      notifyListeners();
    });
    p.playerStateStream.listen((_) {
      _countPlay();
      notifyListeners();
    });
    return _player = p;
  }

  Track? get current {
    final i = _index;
    if (i == null || i >= _queue.length) return null;
    // Rilegge il brano dalla libreria, così le modifiche ai metadati si vedono subito.
    final id = _queue[i].id;
    for (final t in library.tracks) {
      if (t.id == id) return t;
    }
    return _queue[i];
  }

  bool get isPlaying => _player?.playing ?? false;

  /// Un ascolto conta quando il brano comincia davvero a suonare.
  void _countPlay() {
    final i = _index;
    if (!isPlaying || i == null || i >= _queue.length || _counted == (_generation, i)) return;
    _counted = (_generation, i);
    library.recordPlay(_queue[i].id).catchError((_) {});
  }

  Future<void> playQueue(List<Track> tracks, {int start = 0, bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    _index = start;
    _generation++;
    notifyListeners();
    await player.setShuffleModeEnabled(shuffle);
    await player.setAudioSources([
      for (final t in _queue) AudioSource.file(library.audioFile(t).path, tag: t),
    ], initialIndex: start);
    if (shuffle) await player.shuffle();
    await player.play();
  }

  /// Mette [track] subito dopo il brano in riproduzione (o lo avvia, se non suona niente).
  Future<void> playNext(Track track) async {
    final i = _index;
    if (i == null || _queue.isEmpty) return playQueue([track]);
    _queue = [..._queue.take(i + 1), track, ..._queue.skip(i + 1)];
    await player.insertAudioSource(i + 1, AudioSource.file(library.audioFile(track).path, tag: track));
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> next() => player.seekToNext();

  Future<void> previous() async {
    // Come nelle app di musica: dopo i primi secondi "indietro" riavvia il brano.
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  void _onLibraryChanged() {
    // Se il brano in riproduzione viene eliminato, ferma tutto.
    final c = current;
    if (c != null && !library.contains(c.id)) {
      _player?.stop();
      _queue = const [];
      _index = null;
      notifyListeners();
    } else if (c != null) {
      // Metadati modificati: aggiorna il player.
      notifyListeners();
    }
  }

  @override
  void dispose() {
    library.removeListener(_onLibraryChanged);
    _player?.dispose();
    super.dispose();
  }
}
