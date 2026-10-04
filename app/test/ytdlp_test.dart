import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp4player/models/track.dart';
import 'package:mp4player/services/direct_audio.dart';
import 'package:mp4player/services/music_catalog.dart';
import 'package:mp4player/services/ytdlp_audio.dart';
import 'package:mp4player/ui/settings_page.dart';

const channel = MethodChannel('carrots/ytdlp');

/// Il lato Android finto: risponde come YtDlpChannel.kt.
void fakeNative(Future<Object?> Function(MethodCall call) handler) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler);

/// Un messaggio dal lato Android verso Flutter, come `channel.invokeMethod("progress", …)`.
Future<void> fromNative(String method, Object? args) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );

class FallbackAudio implements AudioFetcher {
  final fetched = <String>[];

  @override
  Future<File> fetch(String videoId, File Function(String ext) target, {void Function(double)? onProgress}) async {
    fetched.add(videoId);
    return target('m4a')..writeAsBytesSync([9]);
  }

  @override
  Future<SearchResult?> describe(String videoId) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mp4ytdlp'));
  tearDown(() {
    fakeNative((_) async => null);
    dir.deleteSync(recursive: true);
  });

  test('downloads with yt-dlp on the phone and moves the file into the library', () async {
    final calls = <MethodCall>[];
    fakeNative((call) async {
      calls.add(call);
      final args = Map<String, Object?>.from(call.arguments as Map);
      await fromNative('progress', {'id': args['id'], 'progress': 0.4});
      final out = File('${args['dir']}/audio.m4a')..writeAsBytesSync([1, 2, 3]);
      return out.path;
    });
    final progress = <double>[];
    final fetcher = YtDlpAudioFetcher(ytDlp: YtDlp(), fallback: FallbackAudio(), tempRoot: dir);
    final file = await fetcher.fetch(
      'dQw4w9WgXcQ',
      (ext) => File('${dir.path}/Rick Astley - Never Gonna Give You Up.$ext'),
      onProgress: progress.add,
    );

    expect(file.path, endsWith('Never Gonna Give You Up.m4a'));
    expect(file.readAsBytesSync(), [1, 2, 3]);
    expect(calls.single.method, 'download');
    expect((calls.single.arguments as Map)['url'], 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(progress, [0.4]);
    // La cartella temporanea di yt-dlp sparisce.
    expect(dir.listSync().whereType<Directory>(), isEmpty);
  });

  test('if YouTube says no, the message says what to do; if yt-dlp does not start, the old way is used', () async {
    fakeNative((call) async => throw PlatformException(code: 'ytdlp', message: 'Sign in to confirm you’re not a bot'));
    final fallback = FallbackAudio();
    final fetcher = YtDlpAudioFetcher(ytDlp: YtDlp(), fallback: fallback, tempRoot: dir);
    await expectLater(
      fetcher.fetch('dQw4w9WgXcQ', (ext) => File('${dir.path}/a.$ext')),
      throwsA(isA<CatalogException>().having((e) => e.message, 'message', contains('Aspetta qualche minuto'))),
    );
    expect(fallback.fetched, isEmpty);

    fakeNative((call) async => throw PlatformException(code: 'init', message: 'failed to initialize'));
    final file = await fetcher.fetch('dQw4w9WgXcQ', (ext) => File('${dir.path}/b.$ext'));
    expect(fallback.fetched, ['dQw4w9WgXcQ']);
    expect(file.readAsBytesSync(), [9]);
  });

  testWidgets('settings: shows the yt-dlp version and updates it', (tester) async {
    var version = 'yt-dlp 2025.11.12';
    fakeNative((call) async {
      switch (call.method) {
        case 'version':
          return version;
        case 'update':
          version = 'yt-dlp 2026.09.30';
          return {'updated': true, 'version': version};
      }
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EngineTile(ytDlp: YtDlp())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Motore download'), findsOneWidget);
    expect(find.text('yt-dlp 2025.11.12'), findsOneWidget);

    await tester.tap(find.text('Aggiorna motore download'));
    await tester.pumpAndSettle();
    expect(find.text('yt-dlp 2026.09.30'), findsOneWidget);
    expect(find.text('Aggiornato a yt-dlp 2026.09.30'), findsOneWidget);
  });
}
