import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'direct_audio.dart';
import 'library_store.dart';
import 'music_catalog.dart';
import 'playlist_store.dart';
import 'server_api.dart';
import 'settings.dart';
import 'yt_music.dart';

enum DownloadPhase { server, transfer, done, error }

class DownloadState {
  const DownloadState(this.phase, this.progress, [this.error]);
  final DownloadPhase phase;

  /// Avanzamento complessivo da 0 a 1. Con il server il download sul server pesa l'80%
  /// e il trasferimento sul dispositivo il restante 20%; nell'app conta solo il trasferimento.
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

/// Coordina i download. Due modi:
/// - nell'app ([DownloadMode.device]): cerca su YouTube Music e scarica l'audio direttamente
///   sul dispositivo, senza server (Android e iPhone);
/// - con il server ([DownloadMode.server]): il server scarica con yt-dlp, poi l'app copia il file.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.library,
    required this.api,
    this.playlists,
    this.mode = DownloadMode.server,
    this._music,
    this._audio,
    this.pollInterval = const Duration(milliseconds: 700),
  });

  final LibraryStore library;
  final PlaylistStore? playlists;
  ServerApi api;
  DownloadMode mode;
  MusicCatalog? _music;
  AudioFetcher? _audio;
  final Duration pollInterval;

  /// YouTube Music letto direttamente dall'app.
  MusicCatalog get music => _music ??= YtMusicClient();
  AudioFetcher get audio => _audio ??= YoutubeAudioFetcher();

  /// Dove si cercano brani, album, playlist e artisti nel modo scelto.
  MusicCatalog get catalog => mode == DownloadMode.server ? api : music;

  final Map<String, Future<Discography>> _discographies = {};

  /// La discografia di un artista, chiesta una volta sola finché l'app resta aperta
  /// (se fallisce, la volta dopo si riprova).
  Future<Discography> discography(String artist) {
    final key = '${mode.name}:${artist.trim().toLowerCase()}';
    final cached = _discographies[key];
    if (cached != null) return cached;
    final future = catalog.discography(artist.trim());
    _discographies[key] = future;
    future.then(
      (_) {},
      onError: (Object _) {
        _discographies.remove(key);
      },
    );
    return future;
  }

  final Map<String, DownloadState> _states = {};
  final Map<String, CollectionProgress> _collections = {};

  DownloadState? stateOf(String id) => _states[id];

  CollectionProgress? collectionState(String id) => _collections[id];

  void _set(String id, DownloadState s) {
    _states[id] = s;
    notifyListeners();
  }

  /// [key] identifica la riga nell'interfaccia (l'id del risultato, o il link incollato).
  /// [result] è il brano trovato su YouTube Music, con titolo e artisti principali.
  /// [cover], [album] e [albumArtist] arrivano dall'album o dalla playlist da cui si scarica.
  Future<Track?> download(
    String key, {
    String? source,
    SearchResult? result,
    String? cover,
    String? album,
    String? albumArtist,
  }) async {
    final current = _states[key];
    if (current != null && (current.phase == DownloadPhase.server || current.phase == DownloadPhase.transfer)) {
      return null;
    }
    try {
      final track = mode == DownloadMode.server
          ? await _viaServer(key, source ?? key, result, cover: cover, album: album, albumArtist: albumArtist)
          : await _onDevice(key, source ?? key, result, cover: cover, album: album, albumArtist: albumArtist);
      await library.add(track);
      _set(key, const DownloadState(DownloadPhase.done, 1));
      return track;
    } on Exception catch (e) {
      _set(key, DownloadState(DownloadPhase.error, 0, e.toString()));
      return null;
    }
  }

  Future<Track> _viaServer(
    String key,
    String source,
    SearchResult? result, {
    String? cover,
    String? album,
    String? albumArtist,
  }) async {
    _set(key, const DownloadState(DownloadPhase.server, 0));
    var job = await api.startDownload(
      source,
      cover: cover ?? result?.thumbnail,
      album: album ?? result?.album,
      albumArtist: albumArtist,
      artists: result?.artists,
    );
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
    return Track.fromServer(meta, fileName: fileName, coverFileName: coverName);
  }

  /// Tutto sul dispositivo: i dati da YouTube Music, l'audio da YouTube.
  Future<Track> _onDevice(
    String key,
    String source,
    SearchResult? result, {
    String? cover,
    String? album,
    String? albumArtist,
  }) async {
    _set(key, const DownloadState(DownloadPhase.transfer, 0));
    final videoId = videoIdOf(result?.id ?? source);
    if (videoId == null) throw CatalogException('Serve un id video o un link YouTube');

    var info = result;
    if (info == null) {
      // Un link incollato: titolo e artisti principali dalla coda di YouTube Music,
      // altrimenti dal video (canale + ospiti nel titolo).
      try {
        info = await music.song(videoId);
      } on Exception {
        info = null;
      }
      info ??= await audio.describe(videoId);
    }
    final title = info?.title ?? videoId;
    final artists = info?.artists ?? const <String>[];

    final existing = library.byId(videoId);
    String? written;
    await audio.fetch(videoId, (ext) {
      final name = existing != null && existing.format == ext
          ? existing.fileName
          : library.newAudioName(artists.join(', '), title, ext);
      written = name;
      return library.audioFileFor(name);
    }, onProgress: (p) => _set(key, DownloadState(DownloadPhase.transfer, p * 0.95)));
    // Riscaricato in un altro formato: il file vecchio non serve più.
    if (existing != null && existing.fileName != written) {
      final old = library.audioFile(existing);
      if (await old.exists()) await old.delete();
    }

    String? coverName;
    final thumb = cover ?? info?.thumbnail;
    if (thumb != null && await api.fetchCover(thumb, library.fileFor('$videoId.jpg'))) {
      coverName = '$videoId.jpg';
    }
    return Track(
      id: videoId,
      title: title,
      artist: artists.join(', '),
      artists: artists,
      album: album ?? info?.album,
      duration: info?.duration,
      thumbnail: thumb,
      fileName: written!,
      coverFileName: coverName,
      addedAt: DateTime.now(),
      albumArtist: albumArtist,
      year: info?.year,
      sourceUrl: 'https://music.youtube.com/watch?v=$videoId',
    );
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
              result: r,
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
