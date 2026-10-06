import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dove si scarica la musica: direttamente nell'app o tramite il server yt-dlp.
enum DownloadMode { device, server }

/// Tema dell'app: scuro (come il mockup), chiaro, o come il sistema.
enum ThemeChoice { dark, light, system }

/// Lingua dell'interfaccia. "Come il sistema" vuol dire italiano se il dispositivo è in italiano,
/// altrimenti inglese. Se non si sceglie niente resta l'italiano, come nelle versioni di prima.
enum LanguageChoice { system, italian, english }

/// Impostazioni salvate sul dispositivo: server yt-dlp e cartella della musica.
class Settings extends ChangeNotifier {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  static const _urlKey = 'server_url';
  static const _tokenKey = 'server_token';
  static const _musicDirKey = 'music_dir';
  static const _modeKey = 'download_mode';
  static const _themeKey = 'theme';
  static const _languageKey = 'language';

  ThemeChoice get theme => ThemeChoice.values.where((t) => t.name == _prefs.getString(_themeKey)).firstOrNull ?? ThemeChoice.dark;

  Future<void> setTheme(ThemeChoice theme) async {
    await _prefs.setString(_themeKey, theme.name);
    notifyListeners();
  }

  LanguageChoice get language =>
      LanguageChoice.values.where((l) => l.name == _prefs.getString(_languageKey)).firstOrNull ?? LanguageChoice.italian;

  Future<void> setLanguage(LanguageChoice language) async {
    await _prefs.setString(_languageKey, language.name);
    notifyListeners();
  }

  /// Su telefono si scarica nell'app; su PC c'è già il server (l'installer Windows lo include).
  static DownloadMode get defaultMode =>
      Platform.isAndroid || Platform.isIOS ? DownloadMode.device : DownloadMode.server;

  DownloadMode get downloadMode =>
      DownloadMode.values.where((m) => m.name == _prefs.getString(_modeKey)).firstOrNull ?? defaultMode;

  Future<void> setDownloadMode(DownloadMode mode) async {
    await _prefs.setString(_modeKey, mode.name);
    notifyListeners();
  }

  /// Su PC il server di solito gira sullo stesso computer (l'installer Windows lo include).
  static String get defaultUrl =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux ? 'http://127.0.0.1:8000' : 'http://192.168.1.10:8000';

  String get serverUrl => _prefs.getString(_urlKey) ?? defaultUrl;
  String get token => _prefs.getString(_tokenKey) ?? '';

  /// Cartella della musica scelta dall'utente (null = quella dell'app).
  String? get musicDir => _prefs.getString(_musicDirKey);

  Future<void> setMusicDir(String? path) async {
    if (path == null) {
      await _prefs.remove(_musicDirKey);
    } else {
      await _prefs.setString(_musicDirKey, path);
    }
    notifyListeners();
  }

  Future<void> save({required String serverUrl, required String token}) async {
    await _prefs.setString(_urlKey, serverUrl.trim());
    await _prefs.setString(_tokenKey, token.trim());
    notifyListeners();
  }
}
