import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp4player/main.dart';
import 'package:mp4player/ui/download_page.dart';
import 'package:mp4player/models/track.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mp4player/services/library_store.dart';
import 'package:mp4player/services/lyrics_service.dart';
import 'package:mp4player/services/playlist_store.dart';
import 'package:mp4player/services/settings.dart';
import 'package:mp4player/services/yt_music.dart';
import 'package:mp4player/ui/now_playing_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'direct_download_test.dart' show fakeYtMusic, FakeAudio;

Future<(LibraryStore, PlaylistStore, Settings)> _setUp(
  WidgetTester tester,
  Directory dir, {
  Map<String, Object> prefs = const {},
}) async {
  // Schermo alto come un telefono, così la barra in basso non copre i pulsanti da toccare.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final shared = await SharedPreferences.getInstance();
  final library = LibraryStore(dir);
  final playlists = PlaylistStore(library);
  await tester.runAsync(() async {
    await library.load();
    await playlists.load();
  });
  return (library, playlists, Settings(shared));
}

/// Lascia finire le scritture su disco vere (che nel tempo finto dei test non avanzano).
/// Ogni giro fa avanzare un'operazione: scrittura, rinomina, chiusura della scheda...
Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mp4app'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('empty library leads to downloads, settings and search', (tester) async {
    final (library, playlists, settings) = await _setUp(tester, dir);
    await tester.pumpWidget(Mp4PlayerApp(settings: settings, library: library, playlists: playlists));

    expect(find.text('Libreria'), findsOneWidget);
    expect(find.text('La tua libreria è vuota'), findsOneWidget);
    expect(find.text('Non in riproduzione'), findsOneWidget);

    await tester.tap(find.text('Scarica musica'));
    await tester.pumpAndSettle();
    expect(find.text('Brani, album, playlist o link YouTube'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);

    // Il pulsante "Libreria" della barra in basso torna alla prima pagina.
    await tester.tap(find.byTooltip('Libreria'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text(Settings.defaultUrl), findsOneWidget);
    expect(find.text('CARTELLA DELLA MUSICA'), findsOneWidget);
    expect(find.text(dir.path), findsOneWidget);

    await tester.tap(find.byTooltip('Cerca'));
    await tester.pumpAndSettle();
    expect(find.text('Brani, artisti, album, generi'), findsOneWidget);
  });

  testWidgets('recently added, search and a new playlist', (tester) async {
    final (library, playlists, settings) = await _setUp(tester, dir);
    await tester.runAsync(() async {
      File('${dir.path}/a.m4a').writeAsBytesSync([1, 2, 3]);
      await library.add(
        Track(
          id: 'a',
          title: 'Chandelier',
          artist: 'Sia',
          genre: 'Pop',
          fileName: 'a.m4a',
          addedAt: DateTime(2026, 9, 1),
        ),
      );
    });
    await tester.pumpWidget(Mp4PlayerApp(settings: settings, library: library, playlists: playlists));

    expect(find.text('Aggiunti di recente'), findsOneWidget);
    expect(find.text('Chandelier'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerca'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pop');
    await tester.pump();
    expect(find.text('Chandelier'), findsOneWidget);
    expect(find.text('Cerca "pop" su YouTube'), findsOneWidget);

    await tester.tap(find.byTooltip('Libreria'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlist').first);
    await tester.pumpAndSettle();
    expect(find.text('Cerchi le tue playlist?'), findsOneWidget);
    // I Preferiti ci sono sempre, anche senza playlist.
    expect(find.text('Preferiti'), findsOneWidget);

    await tester.tap(find.text('Nuova playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nome playlist'), 'Estate');
    await tester.tap(find.text('Aggiungi musica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chandelier').last);
    await tester.pump();
    await tester.tap(find.text('Fine').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fine'));
    await _settleIo(tester);

    expect(playlists.playlists.single.name, 'Estate');
    expect(find.text('Estate'), findsOneWidget);
    expect(find.text('AGGIORNATA OGGI'), findsOneWidget);
    expect(find.text('1 brano, 0 minuti'), findsOneWidget);
  });

  testWidgets('like a song, open Preferiti and read the lyrics', (tester) async {
    final (library, playlists, settings) = await _setUp(tester, dir);
    await tester.runAsync(() async {
      File('${dir.path}/a.m4a').writeAsBytesSync([1, 2, 3]);
      await library.add(
        Track(id: 'a', title: 'Chandelier', artist: 'Sia', fileName: 'a.m4a', addedAt: DateTime(2026, 9, 1)),
      );
    });
    final lyrics = LyricsService(
      client: MockClient((req) async {
        expect(req.url.queryParameters['track_name'], 'Chandelier');
        return http.Response('{"plainLyrics": "Party girls don\'t get hurt\\nCan\'t feel anything"}', 200);
      }),
    );
    await tester.pumpWidget(Mp4PlayerApp(settings: settings, library: library, playlists: playlists, lyrics: lyrics));

    await tester.tap(find.text('Brani'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi piace'));
    await _settleIo(tester);
    expect(playlists.isFavorite(library.tracks.single), isTrue);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    // Il testo si cerca da solo aprendo le info del brano, e resta salvato.
    await tester.tap(find.byTooltip('Altre azioni'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Info brano'));
    // Finché il testo arriva gira la rotellina: niente pumpAndSettle.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('TESTO'), find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('TESTO'), findsOneWidget);
    expect(find.textContaining('Party girls'), findsOneWidget);
    expect(library.tracks.single.lyrics, startsWith('Party girls'));
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Libreria'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vedi tutti'));
    await tester.pumpAndSettle();
    expect(find.text('Preferiti'), findsOneWidget);
    expect(find.text('Chandelier'), findsOneWidget);
    expect(find.text('1 brano, 0 minuti'), findsOneWidget);
  });

  testWidgets('artist page: the 5 most played songs with their counts, then every album', (tester) async {
    final (library, playlists, settings) = await _setUp(tester, dir, prefs: {'download_mode': 'device'});
    final songs = [
      ('s1', 'One More Time', 'Discovery', ['Daft Punk']),
      ('s2', 'Aerodynamic', 'Discovery', ['Daft Punk']),
      ('s3', 'Digital Love', 'Discovery', ['Daft Punk']),
      ('s4', 'Get Lucky', 'Random Access Memories', ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers']),
      ('s5', 'Instant Crush', 'Random Access Memories', ['Daft Punk', 'Julian Casablancas']),
      ('s6', 'Lose Yourself to Dance', 'Random Access Memories', ['Daft Punk', 'Pharrell Williams']),
    ];
    final plays = {'s1': 3, 's2': 0, 's3': 1, 's4': 12, 's5': 5, 's6': 7};
    await tester.runAsync(() async {
      for (final (id, title, album, artists) in songs) {
        File('${dir.path}/$id.m4a').writeAsBytesSync([1]);
        await library.add(
          Track(
            id: id,
            title: title,
            artist: artists.join(', '),
            artists: artists,
            album: album,
            fileName: '$id.m4a',
            addedAt: DateTime(2026, 10, 1),
          ),
        );
        for (var i = 0; i < plays[id]!; i++) {
          await library.recordPlay(id);
        }
      }
    });
    await tester.pumpWidget(
      Mp4PlayerApp(
        settings: settings,
        library: library,
        playlists: playlists,
        music: YtMusicClient(client: fakeYtMusic()),
        audio: FakeAudio(),
      ),
    );

    await tester.tap(find.text('Artisti'));
    await tester.pumpAndSettle();
    // Gli ospiti hanno la loro voce, ma niente produttori o autori.
    for (final name in ['Daft Punk', 'Julian Casablancas', 'Nile Rodgers', 'Pharrell Williams']) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text('Daft Punk'));
    await tester.pumpAndSettle();

    expect(find.text('I più ascoltati'), findsOneWidget);
    final top = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    final order = ['Get Lucky', 'Lose Yourself to Dance', 'Instant Crush', 'One More Time', 'Digital Love'];
    final positions = [for (final t in order) top.indexOf(t)];
    expect(positions.every((p) => p >= 0), isTrue);
    expect([...positions]..sort(), positions);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('riproduzione'), findsOneWidget); // Digital Love: 1
    expect(find.text('Aerodynamic'), findsNothing); // il sesto non c'è

    await tester.dragUntilVisible(find.text('Homework'), find.byType(CustomScrollView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    // Gli album da YouTube Music: quelli già in libreria lo dicono.
    expect(find.text('Random Access Memories'), findsOneWidget);
    expect(find.text('2013 · In libreria'), findsOneWidget);
    expect(find.text('2001 · In libreria'), findsOneWidget);
    expect(find.text('1997'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Singoli ed EP'),
      find.byType(CustomScrollView).last,
      const Offset(0, -300),
    );
    expect(find.text('Singoli ed EP'), findsOneWidget);

    // Un album che manca si apre per scaricarlo.
    await tester.tap(find.text('Homework'));
    await tester.pumpAndSettle();
    expect(find.byType(CollectionPage), findsOneWidget);
  });

  testWidgets('in the player, tapping an artist name opens that artist', (tester) async {
    final (library, playlists, settings) = await _setUp(tester, dir, prefs: {'download_mode': 'device'});
    final track = Track(
      id: 's4',
      title: 'Get Lucky',
      artist: 'Daft Punk, Pharrell Williams',
      artists: const ['Daft Punk', 'Pharrell Williams'],
      album: 'Random Access Memories',
      fileName: 's4.m4a',
      addedAt: DateTime(2026, 10, 1),
    );
    await tester.runAsync(() async {
      File('${dir.path}/s4.m4a').writeAsBytesSync([1]);
      await library.add(track);
    });
    await tester.pumpWidget(
      Mp4PlayerApp(
        settings: settings,
        library: library,
        playlists: playlists,
        music: YtMusicClient(client: fakeYtMusic()),
        audio: FakeAudio(),
      ),
    );
    await tester.pumpAndSettle();
    // La stessa riga del player, "Daft Punk, Pharrell Williams — Random Access Memories".
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Center(
                child: ArtistLine(track: track, color: Colors.white),
              ),
            ),
          ),
        );
    await tester.pumpAndSettle();
    expect(find.byType(ArtistLine), findsOneWidget);
    expect(find.text('Daft Punk, Pharrell Williams — Random Access Memories', findRichText: true), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('Daft Punk'));
    await tester.pumpAndSettle();
    expect(find.text('I più ascoltati'), findsOneWidget);
    expect(find.text('Daft Punk'), findsWidgets);
  });
}
