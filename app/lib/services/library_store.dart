import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/track.dart';

/// La libreria locale: i file audio e un indice JSON in una cartella dell'app.
class LibraryStore extends ChangeNotifier {
  LibraryStore(this.dir);

  final Directory dir;
  final List<Track> _tracks = [];

  File get _index => File('${dir.path}/library.json');

  /// Brani dal più recente.
  List<Track> get tracks => List.unmodifiable(_tracks);

  File fileFor(String name) => File('${dir.path}/$name');

  File audioFile(Track t) => fileFor(t.fileName);

  File? coverFile(Track t) => t.coverFileName == null ? null : fileFor(t.coverFileName!);

  bool contains(String id) => _tracks.any((t) => t.id == id);

  Future<void> load() async {
    await dir.create(recursive: true);
    _tracks.clear();
    if (await _index.exists()) {
      final raw = jsonDecode(await _index.readAsString()) as List;
      for (final item in raw) {
        final track = Track.fromJson(item as Map<String, dynamic>);
        // Ignora i brani il cui file è sparito.
        if (await audioFile(track).exists()) _tracks.add(track);
      }
    }
    _sort();
    notifyListeners();
  }

  Future<void> add(Track track) async {
    _tracks
      ..removeWhere((t) => t.id == track.id)
      ..add(track);
    _sort();
    await _save();
    notifyListeners();
  }

  Future<void> remove(Track track) async {
    _tracks.removeWhere((t) => t.id == track.id);
    for (final f in [audioFile(track), coverFile(track)]) {
      if (f != null && await f.exists()) await f.delete();
    }
    await _save();
    notifyListeners();
  }

  void _sort() => _tracks.sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Future<void> _save() async {
    final tmp = File('${_index.path}.tmp');
    await tmp.writeAsString(jsonEncode(_tracks.map((t) => t.toJson()).toList()));
    await tmp.rename(_index.path);
  }
}
