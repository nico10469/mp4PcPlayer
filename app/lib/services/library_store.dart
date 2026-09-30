import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/track.dart';
import 'tags.dart';

/// La libreria locale. I file audio stanno nella cartella della musica (scelta dall'utente
/// nelle Impostazioni, o quella dell'app); indice, copertine e playlist nella cartella dell'app.
class LibraryStore extends ChangeNotifier {
  LibraryStore(this.dir, {Directory? musicDir}) : _musicDir = musicDir ?? dir;

  /// Cartella dell'app: `library.json`, `playlists.json` e le copertine.
  final Directory dir;
  Directory _musicDir;
  final List<Track> _tracks = [];

  /// Brani il cui file ora non si trova (cartella non raggiungibile, permesso tolto...):
  /// restano nell'indice, così ricompaiono appena la cartella torna accessibile.
  final List<Track> _missing = [];

  static const audioExtensions = {'m4a', 'mp3', 'flac', 'ogg', 'opus', 'wav', 'aac', 'webm', 'mp4'};

  /// Cartella in cui stanno i file audio.
  Directory get musicDir => _musicDir;

  /// true se l'utente ha scelto una cartella sua invece di quella dell'app.
  bool get usesCustomFolder => _musicDir.absolute.path != dir.absolute.path;

  File get _index => File('${dir.path}/library.json');

  /// Brani dal più recente.
  List<Track> get tracks => List.unmodifiable(_tracks);

  /// Id di tutti i brani, anche di quelli il cui file adesso non si trova.
  Set<String> get knownIds => {for (final t in _tracks) t.id, for (final t in _missing) t.id};

  /// File nella cartella dell'app (copertine, playlist).
  File fileFor(String name) => File('${dir.path}/$name');

  /// File audio nella cartella della musica.
  File audioFileFor(String name) => File('${_musicDir.path}/$name');

  File audioFile(Track t) => audioFileFor(t.fileName);

  File? coverFile(Track t) => t.coverFileName == null ? null : fileFor(t.coverFileName!);

  bool contains(String id) => _tracks.any((t) => t.id == id);

  Track? byId(String id) {
    for (final t in _tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> load() async {
    await dir.create(recursive: true);
    _tracks.clear();
    _missing.clear();
    if (await _index.exists()) {
      final raw = jsonDecode(await _index.readAsString()) as List;
      for (final item in raw) {
        final track = Track.fromJson(item as Map<String, dynamic>);
        (await audioFile(track).exists() ? _tracks : _missing).add(track);
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

  /// Sostituisce i metadati di un brano già presente (stesso id), senza cambiarne la posizione.
  Future<void> update(Track track) async {
    final i = _tracks.indexWhere((t) => t.id == track.id);
    if (i < 0) return;
    _tracks[i] = track;
    await _save();
    notifyListeners();
  }

  /// Copia l'immagine [source] come nuova copertina del brano.
  Future<void> setCover(Track track, File source) async {
    final current = byId(track.id) ?? track;
    final dot = source.path.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : source.path.substring(dot + 1).toLowerCase();
    // Nome nuovo a ogni cambio, così l'immagine vecchia non resta nella cache di Flutter.
    final name = '${current.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await source.copy(fileFor(name).path);
    final old = coverFile(current);
    await update(current.copyWith(coverFileName: name));
    if (old != null && await old.exists()) await old.delete();
  }

  Future<void> remove(Track track) async {
    _tracks.removeWhere((t) => t.id == track.id);
    for (final f in [audioFile(track), coverFile(track)]) {
      if (f != null && await f.exists()) await f.delete();
    }
    await _save();
    notifyListeners();
  }

  /// Nome leggibile e non ancora usato per un nuovo file audio: "Artista - Titolo.m4a".
  String newAudioName(String artist, String title, String ext) {
    var base = [artist, title].where((s) => s.trim().isNotEmpty).join(' - ');
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    base = base.replaceAll(RegExp(r'[. ]+$'), '');
    if (base.length > 120) base = base.substring(0, 120).trim();
    if (base.isEmpty) base = 'Brano';
    final used = {
      for (final t in [..._tracks, ..._missing]) t.fileName.toLowerCase(),
    };
    var name = '$base.$ext';
    for (var i = 2; used.contains(name.toLowerCase()) || audioFileFor(name).existsSync(); i++) {
      name = '$base ($i).$ext';
    }
    return name;
  }

  /// Usa [target] come cartella della musica e ci sposta i brani, con nomi leggibili.
  /// Prima copia tutto e solo alla fine cancella gli originali: se qualcosa va storto
  /// (spazio finito, permesso negato) la libreria resta com'era. Restituisce i brani spostati.
  Future<int> moveTo(Directory target) async {
    await target.create(recursive: true);
    if (target.absolute.path == _musicDir.absolute.path) return 0;
    final old = _musicDir;
    _musicDir = target;
    final copied = <(int, File, String)>[];
    try {
      for (var i = 0; i < _tracks.length; i++) {
        final t = _tracks[i];
        final src = File('${old.path}/${t.fileName}');
        if (!await src.exists()) continue;
        final name = newAudioName(t.artist, t.title, t.format.isEmpty ? 'm4a' : t.format);
        await src.copy(audioFileFor(name).path);
        copied.add((i, src, name));
      }
    } catch (_) {
      for (final (_, _, name) in copied) {
        await audioFileFor(name).delete().catchError((_) => File(''));
      }
      _musicDir = old;
      rethrow;
    }
    for (final (i, _, name) in copied) {
      _tracks[i] = _tracks[i].copyWith(fileName: name);
    }
    // I brani che mancavano potrebbero essere già nella cartella nuova.
    for (final t in List.of(_missing)) {
      if (await audioFile(t).exists()) {
        _missing.remove(t);
        _tracks.add(t);
      }
    }
    _sort();
    await _save();
    notifyListeners();
    for (final (_, src, _) in copied) {
      await src.delete().catchError((_) => src);
    }
    return copied.length;
  }

  /// Aggiunge alla libreria i file audio della cartella della musica che non conosce ancora
  /// (anche nelle sottocartelle), leggendo titolo, artista, copertina e testo dai tag.
  Future<int> importFolder() async {
    if (!await _musicDir.exists()) return 0;
    final known = {
      for (final t in [..._tracks, ..._missing]) t.fileName,
    };
    final root = _musicDir.path.endsWith(Platform.pathSeparator)
        ? _musicDir.path
        : '${_musicDir.path}${Platform.pathSeparator}';
    final found = <String>[];
    try {
      await for (final entry in _musicDir.list(recursive: true, followLinks: false)) {
        if (entry is! File || !entry.path.startsWith(root)) continue;
        final rel = entry.path.substring(root.length).replaceAll(Platform.pathSeparator, '/');
        if (rel.split('/').any((part) => part.startsWith('.'))) continue;
        final dot = rel.lastIndexOf('.');
        if (dot < 0 || !audioExtensions.contains(rel.substring(dot + 1).toLowerCase())) continue;
        if (!known.contains(rel)) found.add(rel);
      }
    } on FileSystemException {
      // Una sottocartella non leggibile: si importa quello che si è trovato finora.
    }
    if (found.isEmpty) return 0;

    final ids = knownIds;
    for (final rel in found) {
      final file = audioFileFor(rel);
      final tags = await readTags(file);
      var id = 'local_${_hash(rel)}';
      while (ids.contains(id)) {
        id = '${id}x';
      }
      ids.add(id);

      String? coverName;
      if (tags?.cover != null) {
        coverName = '$id.${tags!.coverMime == 'image/png' ? 'png' : 'jpg'}';
        await fileFor(coverName).writeAsBytes(tags.cover!);
      }
      // Senza tag si prova "Artista - Titolo" dal nome del file.
      final stem = rel.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final parts = stem.split(' - ');
      final fromName = parts.length >= 2 ? (parts.first.trim(), parts.skip(1).join(' - ').trim()) : ('', stem);
      DateTime added;
      try {
        added = await file.lastModified();
      } on FileSystemException {
        added = DateTime.now();
      }
      _tracks.add(
        Track(
          id: id,
          title: _orNull(tags?.title) ?? fromName.$2,
          artist: _orNull(tags?.artist) ?? fromName.$1,
          album: _orNull(tags?.album),
          duration: tags?.duration,
          fileName: rel,
          coverFileName: coverName,
          addedAt: added,
          albumArtist: _orNull(tags?.albumArtist),
          genre: _orNull(tags?.genre),
          year: tags?.year,
          lyrics: _orNull(tags?.lyrics),
        ),
      );
    }
    _sort();
    await _save();
    notifyListeners();
    return found.length;
  }

  static String? _orNull(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  /// FNV-1a a 32 bit: un id stabile per lo stesso percorso.
  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(s)) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  void _sort() => _tracks.sort((a, b) => b.addedAt.compareTo(a.addedAt));

  Future<void> _save() async {
    final tmp = File('${_index.path}.tmp');
    await tmp.writeAsString(jsonEncode([..._tracks, ..._missing].map((t) => t.toJson()).toList()));
    await tmp.rename(_index.path);
  }
}
