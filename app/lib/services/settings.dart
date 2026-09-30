import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Impostazioni salvate sul dispositivo: server yt-dlp e cartella della musica.
class Settings extends ChangeNotifier {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  static const _urlKey = 'server_url';
  static const _tokenKey = 'server_token';
  static const _musicDirKey = 'music_dir';

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
