import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Indirizzo e token del server yt-dlp, salvati sul dispositivo.
class Settings extends ChangeNotifier {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  static const _urlKey = 'server_url';
  static const _tokenKey = 'server_token';

  String get serverUrl => _prefs.getString(_urlKey) ?? 'http://192.168.1.10:8000';
  String get token => _prefs.getString(_tokenKey) ?? '';

  Future<void> save({required String serverUrl, required String token}) async {
    await _prefs.setString(_urlKey, serverUrl.trim());
    await _prefs.setString(_tokenKey, token.trim());
    notifyListeners();
  }
}
