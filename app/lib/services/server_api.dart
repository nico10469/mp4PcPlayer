import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/track.dart';

class ServerException implements Exception {
  ServerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Client per il server yt-dlp (cartella `server/` del repository).
class ServerApi {
  ServerApi({required this.baseUrl, this.token = '', http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;

  Map<String, String> get _headers => {
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<dynamic> _json(Future<http.Response> request) async {
    final http.Response res;
    try {
      res = await request.timeout(const Duration(seconds: 30));
    } on Exception catch (e) {
      throw ServerException('Server non raggiungibile ($e)');
    }
    if (res.statusCode == 401) throw ServerException('Token errato');
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        detail = (jsonDecode(res.body) as Map)['detail'].toString();
      } catch (_) {}
      throw ServerException('Errore ${res.statusCode}: $detail');
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  /// Restituisce la versione di yt-dlp installata sul server.
  Future<String> health() async {
    final data = await _json(_client.get(_uri('/health'), headers: _headers)) as Map<String, dynamic>;
    return data['yt_dlp'] as String;
  }

  Future<List<SearchResult>> search(String query) async {
    final data = await _json(_client.get(_uri('/search', {'q': query}), headers: _headers)) as List;
    return data.map((e) => SearchResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// [source] è un id video o un link YouTube.
  Future<ServerJob> startDownload(String source) async {
    final data = await _json(_client.post(_uri('/downloads'), headers: _headers, body: jsonEncode({'source': source})));
    return ServerJob.fromJson(data as Map<String, dynamic>);
  }

  Future<ServerJob> job(String jobId) async {
    final data = await _json(_client.get(_uri('/downloads/$jobId'), headers: _headers));
    return ServerJob.fromJson(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> track(String trackId) async {
    return await _json(_client.get(_uri('/tracks/$trackId'), headers: _headers)) as Map<String, dynamic>;
  }

  /// Scarica il file audio del brano in [target], riportando l'avanzamento da 0 a 1.
  Future<void> fetchFile(String trackId, File target, {void Function(double)? onProgress}) async {
    await _fetch(_uri('/tracks/$trackId/file'), target, headers: _headers, onProgress: onProgress);
  }

  /// Scarica la copertina. Restituisce false se non è disponibile.
  Future<bool> fetchCover(String url, File target) async {
    try {
      await _fetch(Uri.parse(url), target);
      return true;
    } on Exception {
      return false;
    }
  }

  Future<void> _fetch(Uri uri, File target, {Map<String, String>? headers, void Function(double)? onProgress}) async {
    final req = http.Request('GET', uri)..headers.addAll(headers ?? const {});
    final res = await _client.send(req);
    if (res.statusCode != 200) {
      throw ServerException('Errore ${res.statusCode} scaricando $uri');
    }
    final total = res.contentLength ?? 0;
    final tmp = File('${target.path}.part');
    final sink = tmp.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
    await tmp.rename(target.path);
  }
}
