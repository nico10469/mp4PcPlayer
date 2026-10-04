import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide SearchResult;

import '../models/track.dart';
import 'music_catalog.dart';

/// Scarica l'audio di un video YouTube direttamente sul dispositivo, senza server.
abstract class AudioFetcher {
  /// Scrive l'audio in `target(estensione)` e restituisce il file scritto.
  Future<File> fetch(String videoId, File Function(String ext) target, {void Function(double)? onProgress});

  /// Titolo, canale e durata del video, quando YouTube Music non lo conosce.
  Future<SearchResult?> describe(String videoId);
}

/// Usa youtube_explode_dart: niente Python, quindi funziona anche su iPhone.
class YoutubeAudioFetcher implements AudioFetcher {
  YoutubeAudioFetcher({YoutubeExplode? yt}) : _yt = yt ?? YoutubeExplode();

  final YoutubeExplode _yt;

  Future<StreamManifest> _manifest(String videoId) async {
    try {
      return await _yt.videos.streamsClient.getManifest(videoId);
    } on Exception {
      // Se i client predefiniti vengono rifiutati si provano quelli che di solito non chiedono
      // la firma del link (gli stessi che usa yt-dlp quando gli altri non vanno).
      return _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [YoutubeApiClient.androidVr, YoutubeApiClient.ios],
      );
    }
  }

  @override
  Future<File> fetch(String videoId, File Function(String ext) target, {void Function(double)? onProgress}) async {
    final StreamManifest manifest;
    try {
      manifest = await _manifest(videoId);
    } on Exception catch (e) {
      throw CatalogException('YouTube non ha dato l\'audio del brano ($e)');
    }
    final stream = pickAudio(manifest.audioOnly, iosOnly: Platform.isIOS);
    if (stream == null) throw CatalogException('Nessun audio disponibile per questo brano');

    // L'AAC in contenitore mp4 si salva come .m4a: si riproduce ovunque, iPhone compreso.
    final ext = stream.container == StreamContainer.mp4 ? 'm4a' : stream.container.name;
    final file = target(ext);
    final tmp = File('${file.path}.part');
    final total = stream.size.totalBytes;
    final sink = tmp.openWrite();
    var received = 0;
    try {
      await for (final chunk in _yt.videos.streamsClient.get(stream)) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0, 1).toDouble());
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    if (await file.exists()) await file.delete();
    return tmp.rename(file.path);
  }

  @override
  Future<SearchResult?> describe(String videoId) async {
    try {
      final v = await _yt.videos.get(videoId);
      final author = v.author.replaceFirst(RegExp(r' - Topic$'), '');
      return SearchResult(
        id: videoId,
        title: v.title,
        artists: mainArtistsFromVideo(author, v.title),
        duration: v.duration,
        thumbnail: v.thumbnails.highResUrl,
      );
    } on Exception {
      return null;
    }
  }
}

/// L'audio migliore: AAC (mp4) se c'è, altrimenti, tranne su iPhone, anche Opus (webm).
AudioOnlyStreamInfo? pickAudio(List<AudioOnlyStreamInfo> streams, {bool iosOnly = false}) {
  final aac = streams.where((s) => s.container == StreamContainer.mp4).toList();
  if (aac.isNotEmpty) return aac.withHighestBitrate();
  if (iosOnly || streams.isEmpty) return null;
  return streams.withHighestBitrate();
}

/// Per un video che YouTube Music non conosce: il canale è l'artista principale, e gli
/// ospiti si leggono dal titolo ("Brano (feat. A & B)", "Brano ft. A, B").
List<String> mainArtistsFromVideo(String channel, String title) {
  final artists = <String>[if (channel.trim().isNotEmpty) channel.trim()];
  final m = RegExp(r'\b(?:feat\.?|ft\.?|featuring)\s+([^()\[\]]+)', caseSensitive: false).firstMatch(title);
  if (m != null) {
    for (final name in m.group(1)!.split(RegExp(r',|&| and | e | x ', caseSensitive: false))) {
      final n = name.trim();
      if (n.isNotEmpty && !artists.any((a) => a.toLowerCase() == n.toLowerCase())) artists.add(n);
    }
  }
  return artists;
}

/// L'id del video da un id o da un link YouTube / YouTube Music (watch, youtu.be, shorts).
String? videoIdOf(String source) {
  source = source.trim();
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(source)) return source;
  final uri = Uri.tryParse(source);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.firstOrNull;
  } else if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
    id = uri.queryParameters['v'];
    if (id == null && uri.pathSegments.length >= 2 && {'shorts', 'live', 'embed'}.contains(uri.pathSegments[0])) {
      id = uri.pathSegments[1];
    }
  }
  return id != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}
