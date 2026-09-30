import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'library_store.dart';
import 'playlist_store.dart';
import 'server_api.dart';

enum DownloadPhase { server, transfer, done, error }

class DownloadState {
  const DownloadState(this.phase, this.progress, [this.error]);
  final DownloadPhase phase;

  /// Avanzamento complessivo da 0 a 1: il download sul server pesa l'80%,
  /// il trasferimento sul dispositivo il restante 20%.
  final double progress;
  final String? error;
}

/// Avanzamento di "Scarica tutto" su un album o una playlist.
class CollectionProgress {
  const CollectionProgress({required this.done, required this.failed, required this.total, required this.running});
  final int done;
  final int failed;
  final int total;
  final bool running;
}

/// Coordina il flusso: il server scarica da YouTube, poi l'app copia il file in locale.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.library,
    required this.api,
    this.playlists,
    this.pollInterval = const Duration(milliseconds: 700),
  });

  final LibraryStore library;
  final PlaylistStore? playlists;
  ServerApi api;
  final Duration pollInterval;
  final Map<String, DownloadState> _states = {};
  final Map<String, CollectionProgress> _collections = {};

  DownloadState? stateOf(String id) => _states[id];

  CollectionProgress? collectionState(String id) => _collections[id];

  void _set(String id, DownloadState s) {
    _states[id] = s;
    notifyListeners();
  }

  /// [key] identifica la riga nell'interfaccia (l'id del risultato, o il link incollato).
  /// [cover], [album] e [albumArtist] arrivano dalla ricerca su YouTube Music.
  Future<Track?> download(String key, {String? source, String? cover, String? album, String? albumArtist}) async {
    final current = _states[key];
    if (current != null && (current.phase == DownloadPhase.server || current.phase == DownloadPhase.transfer)) {
      return null;
    }
    _set(key, const DownloadState(DownloadPhase.server, 0));
    try {
      var job = await api.startDownload(source ?? key, cover: cover, album: album, albumArtist: albumArtist);
      while (!job.isDone) {
        if (job.isError) throw ServerException(job.error ?? 'Download fallito');
        await Future<void>.delayed(pollInterval);
        job = await api.job(job.id);
        _set(key, DownloadState(DownloadPhase.server, job.progress * 0.8));
      }

      final trackId = job.trackId!;
      final meta = await api.track(trackId);
      // Riscaricando un brano già in libreria si sovrascrive il suo file.
      final fileName =
          library.byId(trackId)?.fileName ??
          library.newAudioName(
            meta['artist'] as String? ?? '',
            meta['title'] as String? ?? trackId,
            meta['ext'] as String? ?? 'm4a',
          );
      await api.fetchFile(
        trackId,
        library.audioFileFor(fileName),
        onProgress: (p) => _set(key, DownloadState(DownloadPhase.transfer, 0.8 + p * 0.2)),
      );

      String? coverName;
      final thumb = meta['thumbnail'] as String?;
      if (thumb != null && await api.fetchCover(thumb, library.fileFor('$trackId.jpg'))) {
        coverName = '$trackId.jpg';
      }

      final track = Track.fromServer(meta, fileName: fileName, coverFileName: coverName);
      await library.add(track);
      _set(key, const DownloadState(DownloadPhase.done, 1));
      return track;
    } on Exception catch (e) {
      _set(key, DownloadState(DownloadPhase.error, 0, e.toString()));
      return null;
    }
  }

  /// Scarica tutti i brani di un album o di una playlist, uno dopo l'altro.
  /// Una playlist diventa anche una playlist dell'app (aggiornata, se era già stata scaricata).
  Future<void> downloadCollection(Collection c) async {
    if (_collections[c.id]?.running ?? false) return;
    var done = 0;
    var failed = 0;
    void report(bool running) {
      _collections[c.id] = CollectionProgress(done: done, failed: failed, total: c.tracks.length, running: running);
      notifyListeners();
    }

    report(true);
    final ids = <String>[];
    for (final r in c.tracks) {
      final track = library.contains(r.id)
          ? library.byId(r.id)
          : await download(
              r.id,
              cover: r.thumbnail ?? c.thumbnail,
              album: c.kind == ResultKind.album ? c.title : r.album,
              albumArtist: c.kind == ResultKind.album && c.artist.isNotEmpty ? c.artist : null,
            );
      if (track != null) {
        ids.add(track.id);
        done++;
      } else {
        failed++;
      }
      report(true);
    }

    final store = playlists;
    if (c.kind == ResultKind.playlist && store != null && ids.isNotEmpty) {
      final existing = store.bySource(c.id);
      if (existing != null) {
        await store.addTracks(existing, ids);
      } else {
        File? cover;
        final thumb = c.thumbnail;
        if (thumb != null) {
          final tmp = File('${library.dir.path}/.cover_${c.id}.jpg');
          if (await api.fetchCover(thumb, tmp)) cover = tmp;
        }
        await store.create(name: c.title, description: c.artist, trackIds: ids, cover: cover, sourceId: c.id);
        if (cover != null && await cover.exists()) await cover.delete();
      }
    }
    report(false);
  }
}
