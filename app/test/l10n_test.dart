import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp4player/main.dart';
import 'package:mp4player/services/library_store.dart';
import 'package:mp4player/services/playlist_store.dart';
import 'package:mp4player/services/settings.dart';
import 'package:mp4player/ui/home_shell.dart';
import 'package:mp4player/ui/l10n.dart';
import 'package:mp4player/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// I testi passati a tr() e plural() nel codice, con le stringhe adiacenti unite come fa Dart.
Set<String> usedTexts() {
  const lit = r"'(?:[^'\\]|\\.)*'";
  final trCall = RegExp(r'\btr\(\s*((?:' + lit + r'\s*)+)');
  final pluralCall = RegExp(r'\bplural\([^,]+,\s*(' + lit + r')\s*,\s*(' + lit + r')');
  String unquote(String group) =>
      RegExp(lit).allMatches(group).map((m) => m[0]!.substring(1, m[0]!.length - 1).replaceAll(r"\'", "'")).join();

  final texts = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final source = f.readAsStringSync();
    for (final m in trCall.allMatches(source)) {
      texts.add(unquote(m[1]!));
    }
    for (final m in pluralCall.allMatches(source)) {
      texts
        ..add(unquote(m[1]!))
        ..add(unquote(m[2]!));
    }
  }
  return texts;
}

void main() {
  tearDown(() {
    appLanguage = AppLanguage.italian;
    AppColors.palette = Palette.dark;
  });

  test('every text of the app has an English translation', () {
    final used = usedTexts();
    expect(used.length, greaterThan(150));
    expect(used.where((t) => !english.containsKey(t)).toList(), isEmpty);
    // Le traduzioni hanno gli stessi segnaposto del testo italiano.
    final placeholder = RegExp(r'\{\w+\}');
    for (final MapEntry(key: it, value: en) in english.entries) {
      final want = placeholder.allMatches(it).map((m) => m[0]).toSet();
      expect(placeholder.allMatches(en).map((m) => m[0]).toSet(), want, reason: it);
    }
  });

  test('tr fills in placeholders, in Italian or English', () {
    expect(tr('Scarica i {n} mancanti', {'n': 3}), 'Scarica i 3 mancanti');
    expect(plural(1, '1 brano', '{n} brani'), '1 brano');
    appLanguage = AppLanguage.english;
    expect(tr('Scarica i {n} mancanti', {'n': 3}), 'Download the 3 missing');
    expect(plural(4, '1 brano', '{n} brani'), '4 songs');
    // Un testo senza traduzione resta com'è.
    expect(tr('Carrots MP4'), 'Carrots MP4');
    expect(resolveLanguage(LanguageChoice.system, const Locale('it', 'IT')), AppLanguage.italian);
    expect(resolveLanguage(LanguageChoice.system, const Locale('de')), AppLanguage.english);
  });

  group('look and layout', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('mp4look'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Settings> pump(WidgetTester tester, Size size, {Map<String, Object> prefs = const {}}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(prefs);
      final settings = Settings(await SharedPreferences.getInstance());
      final library = LibraryStore(dir);
      final playlists = PlaylistStore(library);
      await tester.runAsync(() async {
        await library.load();
        await playlists.load();
      });
      await tester.pumpWidget(Mp4PlayerApp(settings: settings, library: library, playlists: playlists));
      await tester.pumpAndSettle();
      return settings;
    }

    testWidgets('on a wide screen the sections are in a sidebar', (tester) async {
      await pump(tester, const Size(1280, 800));
      expect(MediaQuery.sizeOf(tester.element(find.byType(HomeShell))).width, greaterThan(wideLayoutWidth));
      // Il mini player con avanti e indietro, e niente pulsanti tondi del telefono.
      expect(find.byTooltip('Successivo'), findsOneWidget);
      expect(find.text('Carrots MP4'), findsOneWidget);

      // La voce "Impostazioni" della barra laterale apre le Impostazioni.
      await tester.tap(find.text('Impostazioni').first);
      await tester.pumpAndSettle();
      expect(find.text('CARTELLA DELLA MUSICA'), findsOneWidget);
    });

    testWidgets('switching to English and to the light theme redraws the app', (tester) async {
      final settings = await pump(tester, const Size(390, 844));
      expect(find.text('Libreria'), findsOneWidget);
      expect(AppColors.isDark, isTrue);

      await settings.setLanguage(LanguageChoice.english);
      await settings.setTheme(ThemeChoice.light);
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Your library is empty'), findsOneWidget);
      expect(AppColors.isDark, isFalse);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.backgroundColor ?? Theme.of(tester.element(find.byType(Scaffold).last)).scaffoldBackgroundColor,
          Palette.light.background);
    });
  });
}
