import 'dart:io';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/library_store.dart';
import 'theme.dart';

/// L'immagine della copertina di un brano: la copia locale se c'è, altrimenti quella online.
ImageProvider? coverImage(LibraryStore library, Track track) {
  final f = library.coverFile(track);
  if (f != null && f.existsSync()) return FileImage(f);
  final url = track.thumbnail;
  return url == null ? null : NetworkImage(url);
}

/// Copertina quadrata: file locale se c'è, altrimenti URL, altrimenti una nota musicale.
class Cover extends StatelessWidget {
  const Cover({
    super.key,
    this.file,
    this.url,
    this.size = 48,
    this.radius = 6,
    this.placeholderIcon = Icons.music_note,
    this.placeholderColor,
  });

  /// Copertina di un brano della libreria.
  factory Cover.track(LibraryStore library, Track track, {double size = 48, double radius = 6}) =>
      Cover(file: library.coverFile(track), url: track.thumbnail, size: size, radius: radius);

  final File? file;
  final String? url;
  final double size;
  final double radius;
  final IconData placeholderIcon;

  /// Il colore della nota al posto della copertina (di solito il grigio del tema).
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surfaceHigh,
      alignment: Alignment.center,
      child: Icon(placeholderIcon, color: placeholderColor ?? AppColors.textSecondary, size: size * 0.45),
    );
    Widget image = placeholder;
    final f = file;
    if (f != null && f.existsSync()) {
      image = Image.file(f, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
    } else if (url != null) {
      image = Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(dimension: size, child: image),
    );
  }
}
