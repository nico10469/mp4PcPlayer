import 'dart:io';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Copertina quadrata: file locale se c'è, altrimenti URL, altrimenti una nota musicale.
class Cover extends StatelessWidget {
  const Cover({super.key, this.file, this.url, this.size = 48, this.radius = 6});

  final File? file;
  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surfaceHigh,
      alignment: Alignment.center,
      child: Icon(Icons.music_note, color: AppColors.textSecondary, size: size * 0.45),
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
