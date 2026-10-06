import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Copertina di una playlist: l'immagine scelta dall'utente, altrimenti l'icona rossa del mockup.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({super.key, required this.playlist, this.size = 80, this.radius = 6});

  final Playlist playlist;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Cover(
      file: AppScope.of(context).playlists.coverFile(playlist),
      size: size,
      radius: radius,
      placeholderIcon: Icons.queue_music,
      placeholderColor: AppColors.accent,
    );
  }
}

/// Apre la scheda "Nuova playlist" (quinta immagine del mockup), o la modifica di [playlist].
/// Restituisce la playlist creata.
Future<Playlist?> showPlaylistEditor(
  BuildContext context, {
  Playlist? playlist,
  List<String> initialTrackIds = const [],
}) {
  return showModalBottomSheet<Playlist>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _PlaylistEditor(playlist: playlist, initialTrackIds: initialTrackIds),
    ),
  );
}

class _PlaylistEditor extends StatefulWidget {
  const _PlaylistEditor({this.playlist, required this.initialTrackIds});

  final Playlist? playlist;
  final List<String> initialTrackIds;

  @override
  State<_PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<_PlaylistEditor> {
  late final _name = TextEditingController(text: widget.playlist?.name ?? '');
  late final _description = TextEditingController(text: widget.playlist?.description ?? '');
  late final List<String> _trackIds = List.of(widget.playlist?.trackIds ?? widget.initialTrackIds);
  File? _cover;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picked = await FilePicker.pickFile(type: FileType.image, dialogTitle: tr('Scegli la copertina'));
    final path = picked?.path;
    if (path != null && mounted) setState(() => _cover = File(path));
  }

  Future<void> _addMusic() async {
    final ids = await showTrackPicker(context, exclude: _trackIds.toSet());
    if (ids != null && mounted) setState(() => _trackIds.addAll(ids));
  }

  Future<void> _done() async {
    setState(() => _saving = true);
    final store = AppScope.of(context).playlists;
    final existing = widget.playlist;
    Playlist? result;
    if (existing == null) {
      result = await store.create(name: _name.text, description: _description.text, trackIds: _trackIds, cover: _cover);
    } else {
      await store.edit(existing, name: _name.text, description: _description.text, cover: _cover);
      final current = store.byId(existing.id);
      final added = _trackIds.where((id) => !existing.trackIds.contains(id));
      if (current != null && added.isNotEmpty) await store.addTracks(current, added);
      result = store.byId(existing.id);
    }
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final existing = widget.playlist;
    final byId = {for (final t in scope.library.tracks) t.id: t};
    final tracks = [
      for (final id in _trackIds)
        if (byId[id] != null) byId[id]!,
    ];
    final currentCover = existing == null ? null : scope.playlists.coverFile(existing);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              TextAction(label: tr('Annulla'), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Text(
                  existing == null ? tr('Nuova playlist') : tr('Modifica playlist'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              TextAction(label: tr('Fine'), onPressed: _saving ? null : _done),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickCover,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Cover(
                        file: _cover ?? currentCover,
                        size: 240,
                        radius: 8,
                        placeholderIcon: Icons.queue_music,
                      ),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: AppColors.background, shape: BoxShape.circle),
                        child: Icon(Icons.photo_camera, color: AppColors.text),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                textAlign: TextAlign.center,
                autofocus: existing == null,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: tr('Nome playlist'),
                  filled: false,
                  border: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.divider)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.divider)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: tr('Descrizione'),
                  filled: false,
                  border: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.divider)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.divider)),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_circle, color: Color(0xFF30D158)),
                title: Text(tr('Aggiungi musica'), style: const TextStyle(color: AppColors.accent)),
                onTap: _addMusic,
              ),
              for (final t in tracks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Cover.track(scope.library, t, size: 40),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                  // Nelle playlist già salvate i brani si tolgono dal menu "…" della playlist.
                  trailing: existing != null && existing.trackIds.contains(t.id)
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.remove_circle, color: AppColors.accent),
                          onPressed: () => setState(() => _trackIds.remove(t.id)),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Scelta di più brani dalla libreria. Restituisce gli id scelti, o null se annullato.
Future<List<String>?> showTrackPicker(BuildContext context, {Set<String> exclude = const {}}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    builder: (_) => FractionallySizedBox(heightFactor: 0.9, child: _TrackPicker(exclude: exclude)),
  );
}

class _TrackPicker extends StatefulWidget {
  const _TrackPicker({required this.exclude});

  final Set<String> exclude;

  @override
  State<_TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends State<_TrackPicker> {
  final List<String> _selected = [];
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final q = _filter.toLowerCase();
    final List<Track> tracks = scope.library.tracks
        .where((t) => !widget.exclude.contains(t.id))
        .where((t) => q.isEmpty || t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              TextAction(label: tr('Annulla'), onPressed: () => Navigator.pop(context)),
              Expanded(
                child: Text(
                  tr('Aggiungi musica'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              TextAction(label: tr('Fine'), onPressed: () => Navigator.pop(context, _selected)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: tr('Cerca nella libreria'),
              prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: tracks.isEmpty
              ? EmptyState(title: tr('Nessun brano'), message: tr('Scarica qualcosa per aggiungerlo alle playlist.'))
              : ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    final on = _selected.contains(t.id);
                    return ListTile(
                      leading: Cover.track(scope.library, t, size: 44),
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Icon(
                        on ? Icons.check_circle : Icons.add_circle_outline,
                        color: on ? AppColors.accent : AppColors.textSecondary,
                      ),
                      onTap: () => setState(() => on ? _selected.remove(t.id) : _selected.add(t.id)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
