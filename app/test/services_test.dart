import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:mp4player/models/track.dart';
import 'package:mp4player/services/cover_colors.dart';
import 'package:mp4player/services/download_manager.dart';
import 'package:mp4player/services/library_store.dart';
import 'package:mp4player/services/lyrics_service.dart';
import 'package:mp4player/services/playlist_store.dart';
import 'package:mp4player/services/server_api.dart';

const _id = '2vjPBrBU-TM';

/// Finto server: il primo controllo dice "in corso", il secondo "finito".
MockClient fakeServer({bool failJob = false}) {
  var polls = 0;
  return MockClient((req) async {
    final path = req.url.path;
    if (req.method == 'POST' && path == '/downloads') {
      expect(jsonDecode(req.body), {'source': _id});
      return http.Response(jsonEncode({'id': 'job1', 'status': 'queued', 'progress': 0}), 202);
    }
    if (path == '/downloads/job1') {
      polls++;
      if (failJob) {
        return http.Response(
          jsonEncode({'id': 'job1', 'status': 'error', 'progress': 0, 'error': 'Video unavailable'}),
          200,
        );
      }
      final done = polls >= 2;
      return http.Response(
        jsonEncode({
          'id': 'job1',
          'status': done ? 'done' : 'downloading',
          'progress': done ? 1 : 0.5,
          'track_id': done ? _id : null,
        }),
        200,
      );
    }
    if (path == '/tracks/$_id') {
      return http.Response(
        jsonEncode({
          'id': _id,
          'title': 'Chandelier',
          'artist': 'Sia',
          'album': null,
          'duration': 216.5,
          'thumbnail': 'https://img/x.jpg',
          'ext': 'm4a',
          'genre': 'Pop',
          'year': 2014,
          'source_url': 'https://www.youtube.com/watch?v=$_id',
        }),
        200,
      );
    }
    if (path == '/tracks/$_id/file') return http.Response.bytes(List.filled(10, 7), 200);
    if (req.url.host == 'img') return http.Response.bytes([1, 2, 3], 200);
    if (path == '/search') {
      expect(req.url.queryParameters['q'], 'sia');
      expect(req.url.queryParameters['kind'], 'songs');
      expect(req.headers['Authorization'], 'Bearer t0k');
      return http.Response(
        jsonEncode([
          {'id': _id, 'title': 'Sia - Chandelier', 'artist': 'SiaVEVO', 'duration': 240},
        ]),
        200,
      );
    }
    return http.Response('{"detail":"Not Found"}', 404);
  });
}

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('mp4test'));
  tearDown(() => dir.delete(recursive: true));

  test('search parses results and sends the token', () async {
    final api = ServerApi(baseUrl: 'http://srv:8000/', token: 't0k', client: fakeServer());
    final results = await api.search('sia');
    expect(results.single.title, 'Sia - Chandelier');
    expect(results.single.duration, const Duration(seconds: 240));
    expect(results.single.kind, ResultKind.song);
  });

  test('download saves audio and cover, then survives a reload', () async {
    final library = LibraryStore(dir);
    await library.load();
    final manager = DownloadManager(
      library: library,
      api: ServerApi(baseUrl: 'http://srv:8000', client: fakeServer()),
      pollInterval: Duration.zero,
    );

    final track = await manager.download(_id);
    expect(track!.title, 'Chandelier');
    expect(manager.stateOf(_id)!.phase, DownloadPhase.done);
    expect(await library.audioFile(track).length(), 10);
    expect(await library.coverFile(track)!.readAsBytes(), [1, 2, 3]);

    final reloaded = LibraryStore(dir);
    await reloaded.load();
    expect(reloaded.tracks.single.id, _id);
    expect(reloaded.tracks.single.duration, const Duration(milliseconds: 216500));
    expect(reloaded.tracks.single.genre, 'Pop');
    expect(reloaded.tracks.single.year, 2014);
    expect(reloaded.tracks.single.format, 'm4a');
    // Nella cartella della musica il file ha un nome leggibile.
    expect(reloaded.tracks.single.fileName, 'Sia - Chandelier.m4a');

    await reloaded.remove(reloaded.tracks.single);
    expect(reloaded.tracks, isEmpty);
    expect(await library.audioFile(track).exists(), isFalse);
  });

  test('server error ends in the error state', () async {
    final library = LibraryStore(dir);
    await library.load();
    final manager = DownloadManager(
      library: library,
      api: ServerApi(baseUrl: 'http://srv:8000', client: fakeServer(failJob: true)),
      pollInterval: Duration.zero,
    );
    expect(await manager.download(_id), isNull);
    expect(manager.stateOf(_id)!.phase, DownloadPhase.error);
    expect(manager.stateOf(_id)!.error, contains('Video unavailable'));
    expect(library.tracks, isEmpty);
  });

  test('401 becomes a clear message', () async {
    final api = ServerApi(baseUrl: 'http://srv', client: MockClient((_) async => http.Response('{}', 401)));
    expect(api.health(), throwsA(isA<ServerException>().having((e) => e.message, 'message', 'Token errato')));
  });

  Future<Track> addTrack(LibraryStore library, String id, {String artist = 'Sia'}) async {
    await File('${dir.path}/$id.m4a').writeAsBytes([1]);
    final t = Track(id: id, title: 'T$id', artist: artist, fileName: '$id.m4a', addedAt: DateTime.now());
    await library.add(t);
    return t;
  }

  test('playlists and favorites are saved and follow the library', () async {
    final library = LibraryStore(dir);
    await library.load();
    final a = await addTrack(library, 'a');
    final b = await addTrack(library, 'b');
    final store = PlaylistStore(library);
    await store.load();

    var p = await store.create(name: '  Estate ', description: 'mare', trackIds: ['a']);
    await store.addTracks(p, ['a', 'b']);
    p = store.byId(p.id)!;
    expect(p.name, 'Estate');
    expect(p.trackIds, ['a', 'b']);
    await store.toggleFavorite(b);
    expect(store.isFavorite(b), isTrue);

    store.dispose();
    final reloaded = PlaylistStore(library);
    await reloaded.load();
    expect(reloaded.playlists.single.description, 'mare');
    expect(reloaded.tracksOf(reloaded.playlists.single).map((t) => t.id), ['a', 'b']);
    expect(reloaded.isFavorite(b), isTrue);

    // Eliminare un brano dalla libreria lo toglie anche da playlist e preferiti.
    await library.remove(b);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(reloaded.playlists.single.trackIds, ['a']);
    expect(reloaded.isFavorite(b), isFalse);

    await reloaded.removeTrack(reloaded.playlists.single, a.id);
    expect(reloaded.playlists.single.trackIds, isEmpty);
    await reloaded.delete(reloaded.playlists.single);
    expect(reloaded.playlists, isEmpty);
  });

  test('edited metadata replaces the track in place', () async {
    final library = LibraryStore(dir);
    await library.load();
    final t = await addTrack(library, 'a');
    await library.update(
      t.withMetadata(title: 'Nuovo', artist: 'Sia', album: 'This Is Acting', albumArtist: '', genre: 'Pop', year: 2016),
    );
    final reloaded = LibraryStore(dir);
    await reloaded.load();
    final edited = reloaded.tracks.single;
    expect(
      [edited.title, edited.album, edited.albumArtist, edited.genre, edited.year],
      ['Nuovo', 'This Is Acting', null, 'Pop', 2016],
    );
  });

  test('favorites come newest first and a new folder receives the songs', () async {
    final library = LibraryStore(dir);
    await library.load();
    final a = await addTrack(library, 'a');
    final b = await addTrack(library, 'b', artist: 'Måneskin');
    final store = PlaylistStore(library);
    await store.load();
    await store.toggleFavorite(a);
    await store.toggleFavorite(b);
    expect(store.favoriteTracks.map((t) => t.id), ['b', 'a']);

    final music = Directory('${dir.path}/Musica');
    await music.create();
    // Un file messo a mano nella cartella, senza tag: titolo e artista dal nome.
    await File('${music.path}/Coldplay - Yellow.mp3').writeAsBytes([0, 0, 0]);
    await File('${music.path}/note.txt').writeAsString('non è musica');

    expect(await library.moveTo(music), 2);
    expect(library.musicDir.path, music.path);
    expect(library.usesCustomFolder, isTrue);
    expect(await File('${music.path}/Sia - Ta.m4a').exists(), isTrue);
    expect(await File('${music.path}/Måneskin - Tb.m4a').exists(), isTrue);
    expect(await File('${dir.path}/a.m4a').exists(), isFalse);

    expect(await library.importFolder(), 1);
    final yellow = library.tracks.firstWhere((t) => t.title == 'Yellow');
    expect(yellow.artist, 'Coldplay');
    expect(await library.importFolder(), 0);

    // Riaprendo l'app con la stessa cartella tutto è ancora lì, preferiti compresi.
    final reloaded = LibraryStore(dir, musicDir: music);
    await reloaded.load();
    expect(reloaded.tracks.map((t) => t.title).toSet(), {'Ta', 'Tb', 'Yellow'});
    final favorites = PlaylistStore(reloaded);
    await favorites.load();
    expect(favorites.favoriteTracks.length, 2);
  });

  test('songs whose file is unreachable stay in the index', () async {
    final library = LibraryStore(dir);
    await library.load();
    await addTrack(library, 'a');
    await addTrack(library, 'b');
    final store = PlaylistStore(library);
    await store.load();
    await store.create(name: 'Estate', trackIds: ['a', 'b']);

    await File('${dir.path}/a.m4a').delete();
    final reloaded = LibraryStore(dir);
    await reloaded.load();
    expect(reloaded.tracks.map((t) => t.id), ['b']);
    expect(reloaded.knownIds, {'a', 'b'});
    await reloaded.update(reloaded.tracks.single.copyWith(lyrics: 'la la'));

    // Il file torna: il brano ricompare, ancora nella playlist.
    await File('${dir.path}/a.m4a').writeAsBytes([1]);
    final again = LibraryStore(dir);
    await again.load();
    expect(again.tracks.map((t) => t.id).toSet(), {'a', 'b'});
    final playlists = PlaylistStore(again);
    await playlists.load();
    expect(playlists.playlists.single.trackIds, ['a', 'b']);
    expect(again.byId('b')!.lyrics, 'la la');
  });

  test('a new cover replaces the old one', () async {
    final library = LibraryStore(dir);
    await library.load();
    final t = await addTrack(library, 'a');
    final png = File('${dir.path}/../scelta_${DateTime.now().microsecondsSinceEpoch}.png');
    await png.writeAsBytes([9, 9]);
    await library.setCover(t, png);
    final first = library.coverFile(library.tracks.single)!;
    expect(first.path, endsWith('.png'));
    expect(await first.readAsBytes(), [9, 9]);
    await library.setCover(library.tracks.single, png);
    expect(await first.exists(), isFalse);
    await png.delete();
  });

  test('downloading a playlist saves the songs and a playlist, once', () async {
    final library = LibraryStore(dir);
    await library.load();
    final playlists = PlaylistStore(library);
    await playlists.load();
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path == '/collection') {
        expect(req.url.queryParameters['source'], 'PL1234567890');
        return http.Response(
          jsonEncode({
            'kind': 'playlist',
            'id': 'PL1234567890',
            'title': 'Pop hits',
            'artist': 'YouTube Music',
            'thumbnail': 'https://img/pl.jpg',
            'tracks': [
              {'kind': 'song', 'id': _id, 'title': 'Chandelier', 'artist': 'Sia', 'thumbnail': 'https://img/sq.jpg'},
            ],
          }),
          200,
        );
      }
      if (path == '/downloads') {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'id': 'job1', 'status': 'done', 'progress': 1, 'track_id': _id}), 202);
      }
      if (path == '/tracks/$_id') {
        return http.Response(
          jsonEncode({
            'id': _id,
            'title': 'Chandelier',
            'artist': 'Sia',
            'thumbnail': 'https://img/sq.jpg',
            'ext': 'm4a',
          }),
          200,
        );
      }
      if (path == '/tracks/$_id/file') return http.Response.bytes([1, 2], 200);
      if (req.url.host == 'img') return http.Response.bytes([3], 200);
      return http.Response('{}', 404);
    });
    final manager = DownloadManager(
      library: library,
      playlists: playlists,
      api: ServerApi(baseUrl: 'http://srv', client: client),
      pollInterval: Duration.zero,
    );
    final collection = await manager.api.collection('PL1234567890');
    expect(collection.kind, ResultKind.playlist);
    await manager.downloadCollection(collection);
    expect(bodies.single['cover'], 'https://img/sq.jpg');
    expect(library.tracks.single.id, _id);
    final saved = playlists.playlists.single;
    expect(
      [saved.name, saved.sourceId, saved.trackIds],
      [
        'Pop hits',
        'PL1234567890',
        [_id],
      ],
    );
    expect(playlists.coverFile(saved), isNotNull);
    final progress = manager.collectionState('PL1234567890')!;
    expect([progress.done, progress.failed, progress.running], [1, 0, false]);

    // La seconda volta non si riscarica niente e non nasce una playlist doppia.
    await manager.downloadCollection(collection);
    expect(bodies.length, 1);
    expect(playlists.playlists.length, 1);
  });

  test('lyrics come from LRCLIB, synced ones lose their timestamps', () async {
    final seen = <String>[];
    final service = LyricsService(
      client: MockClient((req) async {
        seen.add(req.url.path);
        expect(req.headers['User-Agent'], contains('Carrots MP4'));
        if (req.url.path == '/api/get') {
          expect(req.url.queryParameters, {
            'track_name': 'Chandelier',
            'artist_name': 'Sia',
            'album_name': '1000 Forms of Fear',
            'duration': '216',
          });
          return http.Response('{"code":404}', 404);
        }
        return http.Response(
          jsonEncode([
            {
              'plainLyrics': null,
              'syncedLyrics': '[00:01.00] Party girls don\'t get hurt\n[00:04.50] Can\'t feel anything',
            },
          ]),
          200,
        );
      }),
    );
    final t = Track(
      id: 'a',
      title: 'Chandelier (Official Video)',
      artist: 'Sia, Diplo',
      album: '1000 Forms of Fear',
      duration: const Duration(seconds: 216),
      fileName: 'a.m4a',
      addedAt: DateTime(2026),
    );
    expect(await service.find(t), "Party girls don't get hurt\nCan't feel anything");
    expect(seen, ['/api/get', '/api/search']);

    final instrumental = LyricsService(client: MockClient((_) async => http.Response('{"instrumental": true}', 200)));
    expect(await instrumental.find(t), '');
  });

  test('dominant color prefers the saturated area over dark pixels', () {
    // 60% quasi nero, 40% rosso: vince il rosso.
    final pixels = BytesBuilder();
    for (var i = 0; i < 60; i++) {
      pixels.add([5, 5, 5, 255]);
    }
    for (var i = 0; i < 40; i++) {
      pixels.add([200, 30, 40, 255]);
    }
    final color = dominantColor(pixels.toBytes())!;
    expect(color, const Color.fromARGB(255, 200, 30, 40));
    expect(foregroundFor(color), const Color(0xFFFFFFFF));
    expect(foregroundFor(const Color(0xFFF5E6A0)), const Color(0xFF000000));
    expect(dominantColor(Uint8List(0)), isNull);
  });
}
