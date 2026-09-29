import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mp4player/services/download_manager.dart';
import 'package:mp4player/services/library_store.dart';
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
        }),
        200,
      );
    }
    if (path == '/tracks/$_id/file') return http.Response.bytes(List.filled(10, 7), 200);
    if (req.url.host == 'img') return http.Response.bytes([1, 2, 3], 200);
    if (path == '/search') {
      expect(req.url.queryParameters['q'], 'sia');
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
}
