import '../models/track.dart';

class CatalogException implements Exception {
  CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Dove si cerca la musica da scaricare: YouTube Music direttamente dall'app
/// (`YtMusicClient`) oppure il server yt-dlp (`ServerApi`).
abstract class MusicCatalog {
  /// Brani (le versioni ufficiali con la sola copertina), album o playlist.
  Future<List<SearchResult>> search(String query, {ResultKind kind = ResultKind.song});

  /// I brani di un album o di una playlist. [source] è l'id o un link YouTube / YouTube Music.
  Future<Collection> collection(String source);

  /// Album, singoli ed EP di un artista.
  Future<Discography> discography(String artist);

  /// Titolo, artisti e album di un brano, per i link incollati (null se non si trova).
  Future<SearchResult?> song(String videoId);
}

/// Una fila di album nella pagina di un artista, con i dati per chiedere l'elenco completo.
class ArtistShelf {
  const ArtistShelf({required this.items, this.browseId, this.params});
  final List<SearchResult> items;
  final String? browseId;
  final String? params;
}

/// La discografia di un artista su YouTube Music.
class Discography {
  const Discography({
    required this.id,
    required this.name,
    this.thumbnail,
    this.albums = const [],
    this.singles = const [],
  });

  final String id;
  final String name;
  final String? thumbnail;
  final List<SearchResult> albums;
  final List<SearchResult> singles;

  factory Discography.fromJson(Map<String, dynamic> json) => Discography(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    thumbnail: json['thumbnail'] as String?,
    albums: [for (final a in json['albums'] as List? ?? const []) SearchResult.fromJson(a as Map<String, dynamic>)],
    singles: [for (final a in json['singles'] as List? ?? const []) SearchResult.fromJson(a as Map<String, dynamic>)],
  );
}
