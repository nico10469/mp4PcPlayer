import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp4player/main.dart';
import 'package:mp4player/models/track.dart';
import 'package:mp4player/services/library_store.dart';
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
    expect(find.text('Artisti, brani o link YouTube'), findsOneWidget);

    // Il pulsante "Libreria" della barra in basso torna alla prima pagina.
    await tester.tap(find.byTooltip('Libreria'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text(Settings.defaultUrl), findsOneWidget);

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
}
