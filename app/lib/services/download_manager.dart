import 'dart:async';
import 'dart:collection';
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
import 'ytdlp_audio.dart';

/// [queued]: aspetta che finisca uno dei download già in corso.
enum DownloadPhase { queued, server, transfer, done, error }

class DownloadState {
  const DownloadState(this.phase, this.progress, [this.error]);
  final DownloadPhase phase;

  /// In fila o in corso: toccare di nuovo "Scarica" non serve.
  bool get isActive => phase == DownloadPhase.queued || phase == DownloadPhase.server || phase == DownloadPhase.transfer;

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
    this.maxParallel = 3,
    this.retryDelay = const Duration(seconds: 3),
  }) : assert(maxParallel > 0);

  final LibraryStore library;
  final PlaylistStore? playlists;
  ServerApi api;
  DownloadMode mode;
  MusicCatalog? _music;
  AudioFetcher? _audio;
  final Duration pollInterval;

  /// Quanti brani si scaricano insieme: abbastanza per andare più veloci, pochi
  /// per non far rallentare YouTube. Gli altri aspettano in fila, nell'ordine.
  final int maxParallel;

  /// Pausa prima di riprovare i brani di un album o di una playlist non riusciti.
  final Duration retryDelay;

  int _running = 0;
  final _waiting = Queue<Completer<void>>();

  Future<void> _acquire() async {
    if (_running < maxParallel) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    // Il posto lo passa direttamente chi finisce (vedi _release): _running non cambia.
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  /// YouTube Music letto direttamente dall'app.
  MusicCatalog get music => _music ??= YtMusicClient();

  /// Su Android yt-dlp vero; altrove (iPhone, computer) le richieste fatte dall'app.
  AudioFetcher get audio => _audio ??= YtDlp.available ? YtDlpAudioFetcher() : YoutubeAudioFetcher();

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
    if (_states[key]?.isActive ?? false) return null;
    _set(key, const DownloadState(DownloadPhase.queued, 0));
    await _acquire();
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
    } finally {
      _release();
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
          reserve: true,
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
          : library.newAudioName(artists.join(', '), title, ext, reserve: true);
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

  /// Scarica tutti i brani di un album o di una playlist, [maxParallel] alla volta.
  /// I brani non riusciti si riprovano una volta alla fine, dopo una pausa.
  /// Una playlist diventa anche una playlist dell'app (aggiornata, se era già stata scaricata).
  Future<void> downloadCollection(Collection c) async {
    if (_collections[c.id]?.running ?? false) return;
    // Un brano ripetuto nella playlist si scarica una volta sola.
    final tracks = {for (final r in c.tracks) r.id: r}.values.toList();
    final found = List<Track?>.filled(tracks.length, null);
    var done = 0;
    var failed = 0;
    void report(bool running) {
      _collections[c.id] = CollectionProgress(done: done, failed: failed, total: tracks.length, running: running);
      notifyListeners();
    }

    Future<bool> get(int i) async {
      final r = tracks[i];
      found[i] =
          library.byId(r.id) ??
          await download(
            r.id,
            result: r,
            cover: r.thumbnail ?? c.thumbnail,
            album: c.kind == ResultKind.album ? c.title : r.album,
            albumArtist: c.kind == ResultKind.album && c.artist.isNotEmpty ? c.artist : null,
          );
      return found[i] != null;
    }

    report(true);
    // Anche se qualcosa va storto, il pulsante "Scarica tutto" torna a funzionare.
    try {
      // Si mettono in fila tutti insieme: download() ne fa partire solo maxParallel alla volta.
      await Future.wait([
        for (var i = 0; i < tracks.length; i++)
          get(i).then((ok) {
            ok ? done++ : failed++;
            report(true);
          }),
      ]);

      // Spesso è stata la connessione, o YouTube che ha rallentato per un attimo.
      final retry = [
        for (var i = 0; i < tracks.length; i++)
          if (found[i] == null) i,
      ];
      if (retry.isNotEmpty) {
        await Future<void>.delayed(retryDelay);
        await Future.wait([
          for (final i in retry)
            get(i).then((ok) {
              if (!ok) return;
              done++;
              failed--;
              report(true);
            }),
        ]);
      }

      // Nella playlist dell'app i brani restano nell'ordine originale, anche se sono finiti in disordine.
      final ids = [
        for (final t in found)
          if (t != null) t.id,
      ];
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
    } finally {
      report(false);
    }
  }
}
