/// Una playlist creata dall'utente. Contiene gli id dei brani, nell'ordine scelto.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.description = '',
    this.coverFileName,
    this.trackIds = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;

  /// Immagine scelta dall'utente, salvata nella cartella della libreria.
  final String? coverFileName;
  final List<String> trackIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist copyWith({String? name, String? description, String? coverFileName, List<String>? trackIds}) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverFileName: coverFileName ?? this.coverFileName,
      trackIds: trackIds ?? this.trackIds,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    coverFileName: json['coverFileName'] as String?,
    trackIds: [for (final id in json['trackIds'] as List? ?? const []) id as String],
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'coverFileName': coverFileName,
    'trackIds': trackIds,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}
