import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mp4player/main.dart';
import 'package:mp4player/services/library_store.dart';
import 'package:mp4player/services/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('empty library leads to the download tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dir = Directory.systemTemp.createTempSync('mp4app');
    final library = LibraryStore(dir);
    await tester.runAsync(library.load);

    await tester.pumpWidget(Mp4PlayerApp(settings: Settings(prefs), library: library));
    expect(find.text('La tua libreria è vuota'), findsOneWidget);

    await tester.tap(find.text('Scarica musica'));
    await tester.pumpAndSettle();
    expect(find.text('Artisti, brani o link YouTube'), findsOneWidget);

    await tester.tap(find.text('Impostazioni').last);
    await tester.pumpAndSettle();
    expect(find.text(Settings.defaultUrl), findsOneWidget);
    dir.deleteSync(recursive: true);
  });
}
