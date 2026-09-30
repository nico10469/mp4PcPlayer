import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp4player/main.dart';
import 'package:mp4player/models/track.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mp4player/services/library_store.dart';
import 'package:mp4player/services/lyrics_service.dart';
import 'package:mp4player/services/playlist_store.dart';
import 'package:mp4player/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(LibraryStore, PlaylistStore, Settings)> _setUp(WidgetTester tester, Directory dir) async {
  // Schermo alto come un telefono, così la barra in basso non copre i pulsanti da toccare.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final library = LibraryStore(dir);
  final playlists = PlaylistStore(library);
  await tester.runAsync(() async {
    await library.load();
    await playlists.load();
  });
  return (library, playlists, Settings(prefs));
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
}
