import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'library_store.dart';

enum PlaylistSort { recent, name }

/// Le playlist e i brani preferiti, salvati in `playlists.json` nella cartella della libreria.
class PlaylistStore extends ChangeNotifier {
  PlaylistStore(this.library) {
    library.addListener(_onLibraryChanged);
  }

  final LibraryStore library;
  final List<Playlist> _playlists = [];
  final Set<String> _favorites = {};

  File get _index => library.fileFor('playlists.json');

  /// Dalla modificata più di recente.
  List<Playlist> get playlists => List.unmodifiable(_playlists);

  List<Playlist> sorted(PlaylistSort sort) {
    final list = List.of(_playlists);
    if (sort == PlaylistSort.name) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  Playlist? byId(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  File? coverFile(Playlist p) => p.coverFileName == null ? null : library.fileFor(p.coverFileName!);

  /// I brani della playlist che sono ancora nella libreria.
  List<Track> tracksOf(Playlist p) {
    final byId = {for (final t in library.tracks) t.id: t};
    return [
      for (final id in p.trackIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  bool isFavorite(Track t) => _favorites.contains(t.id);

  /// I brani con il "mi piace", dall'ultimo aggiunto.
  List<Track> get favoriteTracks {
    final byId = {for (final t in library.tracks) t.id: t};
    return [
      for (final id in _favorites.toList().reversed)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Playlist? bySource(String sourceId) {
    for (final p in _playlists) {
      if (p.sourceId == sourceId) return p;
    }
    return null;
  }

  Future<void> toggleFavorite(Track t) async {
    if (!_favorites.remove(t.id)) _favorites.add(t.id);
    await _save();
    notifyListeners();
  }

  Future<void> load() async {
    _playlists.clear();
    _favorites.clear();
    if (await _index.exists()) {
      final raw = jsonDecode(await _index.readAsString()) as Map<String, dynamic>;
      for (final item in raw['playlists'] as List? ?? const []) {
        _playlists.add(Playlist.fromJson(item as Map<String, dynamic>));
      }
      _favorites.addAll([for (final id in raw['favorites'] as List? ?? const []) id as String]);
    }
    _sort();
    notifyListeners();
  }

  /// [cover] è un'immagine scelta dall'utente: viene copiata nella cartella della libreria.
  Future<Playlist> create({
    required String name,
    String description = '',
    List<String> trackIds = const [],
    File? cover,
    String? sourceId,
  }) async {
    final now = DateTime.now();
    final id = 'pl${now.microsecondsSinceEpoch}';
    var playlist = Playlist(
      id: id,
      name: name.trim().isEmpty ? 'Playlist senza nome' : name.trim(),
      description: description.trim(),
      trackIds: trackIds,
      createdAt: now,
      updatedAt: now,
      sourceId: sourceId,
    );
    if (cover != null) playlist = playlist.copyWith(coverFileName: await _copyCover(id, cover));
    _playlists.add(playlist);
    await _commit();
    return playlist;
  }

  Future<void> edit(Playlist p, {required String name, required String description, File? cover}) async {
    var updated = p.copyWith(name: name.trim().isEmpty ? p.name : name.trim(), description: description.trim());
    if (cover != null) updated = updated.copyWith(coverFileName: await _copyCover(p.id, cover));
    _replace(updated);
    await _commit();
  }

  Future<void> addTracks(Playlist p, Iterable<String> ids) async {
    final current = byId(p.id) ?? p;
    _replace(current.copyWith(trackIds: [...current.trackIds, ...ids.where((id) => !current.trackIds.contains(id))]));
    await _commit();
  }

  Future<void> removeTrack(Playlist p, String trackId) async {
    final current = byId(p.id) ?? p;
    _replace(current.copyWith(trackIds: current.trackIds.where((id) => id != trackId).toList()));
    await _commit();
  }

  Future<void> delete(Playlist p) async {
    _playlists.removeWhere((x) => x.id == p.id);
    final cover = coverFile(p);
    if (cover != null && await cover.exists()) await cover.delete();
    await _commit();
  }

  Future<String> _copyCover(String id, File source) async {
    // Nome nuovo a ogni cambio, così l'immagine vecchia non resta nella cache di Flutter.
    final dot = source.path.lastIndexOf('.');
    final ext = dot < 0 ? 'jpg' : source.path.substring(dot + 1).toLowerCase();
    final name = '${id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await source.copy(library.fileFor(name).path);
    final old = byId(id)?.coverFileName;
    if (old != null) {
      final f = library.fileFor(old);
      if (await f.exists()) await f.delete();
    }
    return name;
  }

  void _replace(Playlist p) {
    final i = _playlists.indexWhere((x) => x.id == p.id);
    if (i >= 0) _playlists[i] = p;
  }

  void _onLibraryChanged() {
    // I brani eliminati dalla libreria spariscono anche dalle playlist e dai preferiti
    // (non quelli il cui file adesso non si trova: tornano quando la cartella è di nuovo raggiungibile).
    final ids = library.knownIds;
    var changed = _favorites.length != _favorites.where(ids.contains).length;
    _favorites.retainWhere(ids.contains);
    for (var i = 0; i < _playlists.length; i++) {
      final p = _playlists[i];
      if (p.trackIds.any((id) => !ids.contains(id))) {
        _playlists[i] = Playlist(
          id: p.id,
          name: p.name,
          description: p.description,
          coverFileName: p.coverFileName,
          trackIds: p.trackIds.where(ids.contains).toList(),
          createdAt: p.createdAt,
          updatedAt: p.updatedAt,
          sourceId: p.sourceId,
        );
        changed = true;
      }
    }
    if (changed) _commit();
  }

  void _sort() => _playlists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _commit() async {
    _sort();
    await _save();
    notifyListeners();
  }

  Future<void> _lastSave = Future.value();

  /// Le scritture vanno in fila, così due salvataggi ravvicinati non si pestano i piedi.
  Future<void> _save() => _lastSave = _lastSave.catchError((_) {}).then((_) => _write());

  Future<void> _write() async {
    final tmp = File('${_index.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'playlists': _playlists.map((p) => p.toJson()).toList(), 'favorites': _favorites.toList()}),
    );
    await tmp.rename(_index.path);
  }

  @override
  void dispose() {
    library.removeListener(_onLibraryChanged);
    super.dispose();
  }
}
