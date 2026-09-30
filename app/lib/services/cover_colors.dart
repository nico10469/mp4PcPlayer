import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Colore dominante di un'immagine, dai suoi pixel RGBA.
///
/// Raggruppa i pixel in 4096 "secchielli" di colore e sceglie quello più grande,
/// favorendo i colori saturi rispetto ai grigi e scartando quasi-nero e quasi-bianco,
/// come fanno le app musicali per lo sfondo del player.
Color? dominantColor(Uint8List rgba) {
  final counts = <int, int>{};
  final sums = <int, List<int>>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    final key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
    counts[key] = (counts[key] ?? 0) + 1;
    final s = sums.putIfAbsent(key, () => [0, 0, 0]);
    s[0] += r;
    s[1] += g;
    s[2] += b;
  }
  if (counts.isEmpty) return null;

  int? best;
  var bestScore = -1.0;
  counts.forEach((key, count) {
    final s = sums[key]!;
    final hsv = HSVColor.fromColor(Color.fromARGB(255, s[0] ~/ count, s[1] ~/ count, s[2] ~/ count));
    var score = count * (0.25 + hsv.saturation);
    if (hsv.value < 0.12 || (hsv.value > 0.95 && hsv.saturation < 0.1)) score *= 0.2;
    if (score > bestScore) {
      bestScore = score;
      best = key;
    }
  });
  final s = sums[best]!;
  final n = counts[best]!;
  return Color.fromARGB(255, s[0] ~/ n, s[1] ~/ n, s[2] ~/ n);
}

/// Colore del testo leggibile sopra [background].
Color foregroundFor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? Colors.white : Colors.black;

final _cache = <String, Color?>{};

/// Calcola (e ricorda per [key]) il colore dominante della copertina [image].
Future<Color?> coverColor(String key, ImageProvider image) async {
  if (_cache.containsKey(key)) return _cache[key];
  final completer = Completer<ui.Image?>();
  final stream = ResizeImage(image, width: 48, height: 48).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (_, _) {
      if (!completer.isCompleted) completer.complete(null);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  final img = await completer.future;
  if (img == null) return _cache[key] = null;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  return _cache[key] = data == null ? null : dominantColor(data.buffer.asUint8List());
}
