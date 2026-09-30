import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';

/// Cerca il testo dei brani, in lingua originale, su LRCLIB (https://lrclib.net):
/// un archivio libero e gratuito che non richiede account né chiavi.
class LyricsService {
  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = 'https://lrclib.net/api';
  static const _headers = {'User-Agent': 'Carrots MP4 (https://github.com/nico10469/mp4PcPlayer)'};

  /// Il testo del brano, "" se il brano è strumentale o il testo non c'è.
  /// Solleva un'eccezione se LRCLIB non si raggiunge (niente internet).
  Future<String> find(Track t) async {
    final artist = t.artist.split(RegExp(r',| & | feat\. | ft\. ', caseSensitive: false)).first.trim();
    final title = cleanTitle(t.title);

    // Prima la ricerca esatta (con album e durata), poi quella più larga.
    final exact = await _get(
      Uri.parse('$_base/get').replace(
        queryParameters: {
          'track_name': title,
          'artist_name': artist,
          if (t.album != null) 'album_name': t.album!,
          if (t.duration != null) 'duration': '${t.duration!.inSeconds}',
        },
      ),
    );
    if (exact is Map<String, dynamic>) {
      final text = _text(exact);
      if (text != null) return text;
    }
    final results = await _get(
      Uri.parse('$_base/search')
          .replace(queryParameters: {'track_name': title, if (artist.isNotEmpty) 'artist_name': artist}),
    );
    if (results is List) {
      for (final r in results.whereType<Map<String, dynamic>>()) {
        final text = _text(r);
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return '';
  }

  Future<Object?> _get(Uri uri) async {
    final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) throw http.ClientException('LRCLIB ha risposto ${res.statusCode}', uri);
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static String? _text(Map<String, dynamic> r) {
    if (r['instrumental'] == true) return '';
    final plain = (r['plainLyrics'] as String?)?.trim();
    if (plain != null && plain.isNotEmpty) return plain;
    final synced = r['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) return stripTimestamps(synced);
    return null;
  }

  /// Toglie i tempi "[01:23.45]" dei testi sincronizzati.
  static String stripTimestamps(String lrc) =>
      lrc.split('\n').map((l) => l.replaceAll(RegExp(r'\[\d+:\d+(?:[.:]\d+)?\]'), '').trim()).join('\n').trim();

  /// "Titolo (Official Video) [HD]" -> "Titolo": le aggiunte dei video non servono per cercare il testo.
  static String cleanTitle(String title) {
    final cleaned = title
        .replaceAll(
          RegExp(
            r'\s*[(\[][^)\]]*(official|video|audio|lyric|testo|hd|4k|visualizer|remaster)[^)\]]*[)\]]',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    return cleaned.isEmpty ? title : cleaned;
  }
}
