/// Un brano salvato sul dispositivo.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.thumbnail,
    required this.fileName,
    this.coverFileName,
    required this.addedAt,
    this.albumArtist,
    this.genre,
    this.year,
    this.sourceUrl,
    this.lyrics,
    this.artists,
  });

  final String id;
  final String title;

  /// Gli artisti come si vedono nell'app ("A, B"). Per i brani scaricati da questa versione
  /// sono solo quelli principali e gli ospiti (feat.), senza produttori e autori.
  final String artist;

  /// Gli stessi artisti uno per uno, per la sezione Artisti. I brani scaricati con le versioni
  /// precedenti non li hanno: per quelli conta [artist] intero.
  final List<String>? artists;

  /// Gli artisti con cui il brano compare nella sezione Artisti.
  List<String> get artistNames {
    final list = [
      for (final a in artists ?? const <String>[])
        if (a.trim().isNotEmpty) a.trim(),
    ];
    if (list.isNotEmpty) return list;
    return [if (artist.trim().isNotEmpty) artist.trim()];
  }

  final String? album;
  final Duration? duration;

  /// URL della copertina su YouTube, usato quando manca la copia locale.
  final String? thumbnail;

  /// Nomi dei file dentro la cartella musica dell'app. Si salvano i nomi e non
  /// i percorsi completi perché su iOS la cartella dell'app cambia a ogni aggiornamento.
  final String fileName;
  final String? coverFileName;
  final DateTime addedAt;

  /// Metadati aggiuntivi da yt-dlp o modificati a mano. I brani scaricati con
  /// le versioni precedenti dell'app non li hanno.
  final String? albumArtist;
  final String? genre;
  final int? year;

  /// Pagina YouTube da cui è stato scaricato.
  final String? sourceUrl;

  /// Testo del brano in lingua originale (dai tag del file, da LRCLIB o scritto a mano).
  /// Una stringa vuota vuol dire che è stato cercato ma non c'è.
  final String? lyrics;

  /// Estensione del file audio (m4a, webm...).
  String get format {
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1);
  }

  /// Copia con i metadati modificati a mano: un testo vuoto cancella il campo.
  Track withMetadata({
    required String title,
    required String artist,
    required String album,
    required String albumArtist,
    required String genre,
    required int? year,
    String? lyrics,
  }) {
    String? orNull(String v) => v.trim().isEmpty ? null : v.trim();
    // Se l'artista è stato cambiato a mano, gli artisti si rileggono dalla virgola.
    final changed = artist.trim() != this.artist.trim();
    return Track(
      id: id,
      title: title.trim().isEmpty ? this.title : title.trim(),
      artist: artist.trim(),
      artists: changed ? splitArtists(artist) : artists,
      album: orNull(album),
      duration: duration,
      thumbnail: thumbnail,
      fileName: fileName,
      coverFileName: coverFileName,
      addedAt: addedAt,
      albumArtist: orNull(albumArtist),
      genre: orNull(genre),
      year: year,
      sourceUrl: sourceUrl,
      lyrics: lyrics == null ? this.lyrics : (lyrics.trim().isEmpty ? null : lyrics.trim()),
    );
  }

  Track copyWith({String? fileName, String? coverFileName, String? lyrics, String? album, String? albumArtist}) {
    return Track(
      id: id,
      title: title,
      artist: artist,
      artists: artists,
      album: album ?? this.album,
      duration: duration,
      thumbnail: thumbnail,
      fileName: fileName ?? this.fileName,
      coverFileName: coverFileName ?? this.coverFileName,
      addedAt: addedAt,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre,
      year: year,
      sourceUrl: sourceUrl,
      lyrics: lyrics ?? this.lyrics,
    );
  }

  /// Costruisce il brano dalla risposta di `GET /tracks/{id}` del server.
  factory Track.fromServer(Map<String, dynamic> json, {required String fileName, String? coverFileName}) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      artists: _strings(json['artists']),
      album: json['album'] as String?,
      duration: _seconds(json['duration']),
      thumbnail: json['thumbnail'] as String?,
      fileName: fileName,
      coverFileName: coverFileName,
      addedAt: DateTime.now(),
      albumArtist: json['album_artist'] as String?,
      genre: json['genre'] as String?,
      year: (json['year'] as num?)?.toInt(),
      sourceUrl: json['source_url'] as String?,
    );
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      artists: _strings(json['artists']),
      album: json['album'] as String?,
      duration: _seconds(json['duration']),
      thumbnail: json['thumbnail'] as String?,
      fileName: json['fileName'] as String,
      coverFileName: json['coverFileName'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int),
      albumArtist: json['albumArtist'] as String?,
      genre: json['genre'] as String?,
      year: (json['year'] as num?)?.toInt(),
      sourceUrl: json['sourceUrl'] as String?,
      lyrics: json['lyrics'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artists': artists,
    'album': album,
    'duration': duration == null ? null : duration!.inMilliseconds / 1000,
    'thumbnail': thumbnail,
    'fileName': fileName,
    'coverFileName': coverFileName,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'albumArtist': albumArtist,
    'genre': genre,
    'year': year,
    'sourceUrl': sourceUrl,
    'lyrics': lyrics,
  };
}

enum ResultKind { song, album, playlist }

/// Un risultato della ricerca su YouTube Music, non ancora scaricato: un brano, un album o una playlist.
class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    this.artists = const [],
    this.kind = ResultKind.song,
    this.album,
    this.albumId,
    this.duration,
    this.thumbnail,
    this.year,
    this.count,
    this.type,
    this.available = true,
  });

  /// Id del video per i brani, id dell'album (MPREb_...) o della playlist per gli altri.
  final String id;
  final String title;

  /// Gli artisti come li elenca YouTube Music (principali e ospiti); per le playlist l'autore.
  final List<String> artists;
  final ResultKind kind;
  final String? album;
  final String? albumId;
  final Duration? duration;
  final String? thumbnail;
  final int? year;

  /// Numero di brani (solo playlist) e tipo di uscita (Album, Singolo, EP).
  final int? count;
  final String? type;

  /// false per i brani che YouTube Music mostra in grigio (non disponibili).
  final bool available;

  String get artist => artists.join(', ');

  SearchResult copyWith({List<String>? artists, String? album, String? albumId, String? thumbnail, int? year}) =>
      SearchResult(
        id: id,
        title: title,
        artists: artists ?? this.artists,
        kind: kind,
        album: album ?? this.album,
        albumId: albumId ?? this.albumId,
        duration: duration,
        thumbnail: thumbnail ?? this.thumbnail,
        year: year ?? this.year,
        count: count,
        type: type,
        available: available,
      );

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    id: json['id'] as String,
    title: json['title'] as String,
    artists: _strings(json['artists']) ?? splitArtists(json['artist'] as String? ?? ''),
    kind: ResultKind.values.firstWhere((k) => k.name == json['kind'], orElse: () => ResultKind.song),
    album: json['album'] as String?,
    albumId: json['album_id'] as String?,
    duration: _seconds(json['duration']),
    thumbnail: json['thumbnail'] as String?,
    year: (json['year'] as num?)?.toInt(),
    count: (json['count'] as num?)?.toInt(),
    type: json['type'] as String?,
  );
}

/// Un album o una playlist di YouTube con i suoi brani.
class Collection {
  const Collection({
    required this.id,
    required this.kind,
    required this.title,
    required this.artist,
    this.thumbnail,
    this.year,
    this.tracks = const [],
  });

  final String id;
  final ResultKind kind;
  final String title;
  final String artist;
  final String? thumbnail;
  final int? year;
  final List<SearchResult> tracks;

  factory Collection.fromJson(Map<String, dynamic> json) => Collection(
    id: json['id'] as String,
    kind: json['kind'] == 'album' ? ResultKind.album : ResultKind.playlist,
    title: json['title'] as String? ?? '',
    artist: json['artist'] as String? ?? '',
    thumbnail: json['thumbnail'] as String?,
    year: (json['year'] as num?)?.toInt(),
    tracks: [for (final t in json['tracks'] as List? ?? const []) SearchResult.fromJson(t as Map<String, dynamic>)],
  );
}

/// Lo stato di un download sul server.
class ServerJob {
  const ServerJob({required this.id, required this.status, required this.progress, this.trackId, this.error});

  final String id;
  final String status; // queued | downloading | done | error
  final double progress;
  final String? trackId;
  final String? error;

  bool get isDone => status == 'done';
  bool get isError => status == 'error';

  factory ServerJob.fromJson(Map<String, dynamic> json) => ServerJob(
    id: json['id'] as String,
    status: json['status'] as String,
    progress: (json['progress'] as num).toDouble(),
    trackId: json['track_id'] as String?,
    error: json['error'] as String?,
  );
}

List<String>? _strings(Object? value) => value is List
    ? [
        for (final v in value)
          if (v is String && v.trim().isNotEmpty) v.trim(),
      ]
    : null;

/// "A, B" → ["A", "B"]. Si divide solo sulla virgola: "Simon & Garfunkel" resta un artista solo.
List<String> splitArtists(String artist) => [
  for (final a in artist.split(','))
    if (a.trim().isNotEmpty) a.trim(),
];

Duration? _seconds(Object? value) => value is num ? Duration(milliseconds: (value * 1000).round()) : null;

String formatDuration(Duration? d) {
  if (d == null) return '';
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
