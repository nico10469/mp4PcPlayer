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

  /// Il player si crea al primo uso, così l'app parte anche dove l'audio non è disponibile (test).
  AudioPlayer get player {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    p.currentIndexStream.listen((i) {
      _index = i;
      notifyListeners();
    });
    p.playerStateStream.listen((_) => notifyListeners());
    return _player = p;
  }

  Track? get current {
    final i = _index;
    return i == null || i >= _queue.length ? null : _queue[i];
  }

  bool get isPlaying => _player?.playing ?? false;

  Future<void> playQueue(List<Track> tracks, {int start = 0, bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    _index = start;
    notifyListeners();
    await player.setShuffleModeEnabled(shuffle);
    await player.setAudioSources([
      for (final t in _queue) AudioSource.file(library.audioFile(t).path, tag: t),
    ], initialIndex: start);
    if (shuffle) await player.shuffle();
    await player.play();
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
    }
  }

  @override
  void dispose() {
    library.removeListener(_onLibraryChanged);
    _player?.dispose();
    super.dispose();
  }
}
