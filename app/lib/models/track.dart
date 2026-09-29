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
  });

  final String id;
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;

  /// URL della copertina su YouTube, usato quando manca la copia locale.
  final String? thumbnail;

  /// Nomi dei file dentro la cartella musica dell'app. Si salvano i nomi e non
  /// i percorsi completi perché su iOS la cartella dell'app cambia a ogni aggiornamento.
  final String fileName;
  final String? coverFileName;
  final DateTime addedAt;

  /// Costruisce il brano dalla risposta di `GET /tracks/{id}` del server.
  factory Track.fromServer(Map<String, dynamic> json, {required String fileName, String? coverFileName}) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String?,
      duration: _seconds(json['duration']),
      thumbnail: json['thumbnail'] as String?,
      fileName: fileName,
      coverFileName: coverFileName,
      addedAt: DateTime.now(),
    );
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String?,
      duration: _seconds(json['duration']),
      thumbnail: json['thumbnail'] as String?,
      fileName: json['fileName'] as String,
      coverFileName: json['coverFileName'] as String?,
      addedAt: DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'duration': duration == null ? null : duration!.inMilliseconds / 1000,
    'thumbnail': thumbnail,
    'fileName': fileName,
    'coverFileName': coverFileName,
    'addedAt': addedAt.millisecondsSinceEpoch,
  };
}

/// Un risultato della ricerca su YouTube, non ancora scaricato.
class SearchResult {
  const SearchResult({required this.id, required this.title, required this.artist, this.duration, this.thumbnail});

  final String id;
  final String title;
  final String artist;
  final Duration? duration;
  final String? thumbnail;

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String? ?? '',
    duration: _seconds(json['duration']),
    thumbnail: json['thumbnail'] as String?,
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

Duration? _seconds(Object? value) => value is num ? Duration(milliseconds: (value * 1000).round()) : null;

String formatDuration(Duration? d) {
  if (d == null) return '';
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
