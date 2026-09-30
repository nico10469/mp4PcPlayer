import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// I tag letti da un file audio (ID3, MP4, Vorbis...).
class FileTags {
  const FileTags({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.lyrics,
    this.duration,
    this.cover,
    this.coverMime,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;
  final int? year;
  final String? lyrics;
  final Duration? duration;
  final Uint8List? cover;
  final String? coverMime;
}

/// Legge i tag di [file] in un isolate a parte, per non bloccare l'interfaccia.
/// Restituisce null se il formato non è supportato o il file è rovinato.
Future<FileTags?> readTags(File file) async {
  try {
    return await Isolate.run(() => _read(file));
  } catch (_) {
    return null;
  }
}

FileTags? _read(File file) {
  try {
    final m = readMetadata(file, getImage: true);
    Picture? cover;
    for (final p in m.pictures) {
      if (p.pictureType == PictureType.coverFront) cover = p;
    }
    cover ??= m.pictures.isEmpty ? null : m.pictures.first;
    final year = m.year?.year;
    return FileTags(
      title: m.title,
      artist: m.artist,
      album: m.album,
      albumArtist: m.albumArtist,
      genre: m.genres.isEmpty ? null : m.genres.first,
      year: year == null || year <= 0 ? null : year,
      lyrics: m.lyrics,
      duration: m.duration,
      cover: cover?.bytes,
      coverMime: cover?.mimetype,
    );
  } catch (_) {
    return null;
  }
}
