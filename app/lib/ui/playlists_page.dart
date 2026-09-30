import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../services/playlist_store.dart';
import 'app_scope.dart';
import 'playlist_editor.dart';
import 'theme.dart';
import 'track_tile.dart';
import 'widgets.dart';

/// Elenco delle playlist (quarta e sesta immagine del mockup).
class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  PlaylistSort _sort = PlaylistSort.recent;
  String _filter = '';

  Future<void> _create() async {
    final created = await showPlaylistEditor(context);
    if (created != null && mounted) openPlaylist(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.playlists,
      builder: (context, _) {
        final all = scope.playlists.sorted(_sort);
        final q = _filter.toLowerCase();
        final shown = q.isEmpty ? all : all.where((p) => p.name.toLowerCase().contains(q)).toList();
        return LargeTitlePage(
          title: 'Playlist',
          backLabel: 'Libreria',
          actions: [
            PopupMenuButton<PlaylistSort>(
              initialValue: _sort,
              color: AppColors.surfaceHigh,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => const [
                PopupMenuItem(value: PlaylistSort.recent, child: Text('Modificate di recente')),
                PopupMenuItem(value: PlaylistSort.name, child: Text('Nome')),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Ordina',
                  style: TextStyle(color: AppColors.accent, fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          slivers: [
            if (all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: 'Cerchi le tue playlist?',
                  message: 'Le playlist che crei compaiono qui.',
                  action: 'Nuova playlist',
                  onAction: _create,
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Cerca nelle playlist',
                      prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                    ),
                    onChanged: (v) => setState(() => _filter = v),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _PlaylistRow(
                  cover: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(6)),
                    child: const Icon(Icons.add, color: AppColors.accent, size: 32),
                  ),
                  title: const Text('Nuova playlist…', style: TextStyle(color: AppColors.accent, fontSize: 18)),
                  onTap: _create,
                ),
              ),
              SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) => _PlaylistRow(
                  cover: PlaylistCover(playlist: shown[i]),
                  title: Text(shown[i].name, style: const TextStyle(fontSize: 18)),
                  subtitle: shown[i].trackIds.length == 1 ? '1 brano' : '${shown[i].trackIds.length} brani',
                  chevron: true,
                  onTap: () => openPlaylist(context, shown[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.cover, required this.title, this.subtitle, this.chevron = false, this.onTap});

  final Widget cover;
  final Widget title;
  final String? subtitle;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
        child: Row(
          children: [
            cover,
            const SizedBox(width: 16),
            Expanded(
              child: Container(
                height: 88,
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          if (subtitle != null)
                            Text(subtitle!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (chevron) const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openPlaylist(BuildContext context, Playlist p) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlaylistPage(playlistId: p.id)));
}

/// Una playlist aperta (settima immagine del mockup).
class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.playlists, scope.library]),
      builder: (context, _) {
        final playlist = scope.playlists.byId(playlistId);
        if (playlist == null) return const Scaffold();
        final tracks = scope.playlists.tracksOf(playlist);
        final total = tracks.fold(Duration.zero, (sum, t) => sum + (t.duration ?? Duration.zero));

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 48,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.accent, size: 20),
                  onPressed: () => Navigator.maybePop(context),
                ),
                actions: [
                  PopupMenuButton<String>(
                    tooltip: 'Opzioni playlist',
                    color: AppColors.surfaceHigh,
                    icon: Container(
                      decoration: const BoxDecoration(color: AppColors.surfaceHigh, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(4),
                      child: const Icon(Icons.more_horiz, color: AppColors.accent, size: 20),
                    ),
                    onSelected: (value) async {
                      switch (value) {
                        case 'edit':
                          await showPlaylistEditor(context, playlist: playlist);
                        case 'add':
                          final ids = await showTrackPicker(context, exclude: playlist.trackIds.toSet());
                          if (ids != null && ids.isNotEmpty) await scope.playlists.addTracks(playlist, ids);
                        case 'delete':
                          if (context.mounted) Navigator.pop(context);
                          await scope.playlists.delete(playlist);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Modifica')),
                      PopupMenuItem(value: 'add', child: Text('Aggiungi musica')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Elimina playlist', style: TextStyle(color: AppColors.accent)),
                      ),
                    ],
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      PlaylistCover(playlist: playlist, size: 220, radius: 10),
                      const SizedBox(height: 20),
                      Text(
                        playlist.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _updated(playlist.updatedAt),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, letterSpacing: 0.5),
                      ),
                      if (playlist.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          playlist.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 20),
                      PlayShuffleRow(
                        onPlay: tracks.isEmpty ? null : () => scope.player.playQueue(tracks),
                        onShuffle: tracks.isEmpty ? null : () => scope.player.playQueue(tracks, shuffle: true),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1, indent: 16)),
              if (tracks.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(
                    title: 'Playlist vuota',
                    message: 'Aggiungi brani dalla tua libreria.',
                    action: 'Aggiungi musica',
                    onAction: () async {
                      final ids = await showTrackPicker(context);
                      if (ids != null && ids.isNotEmpty) await scope.playlists.addTracks(playlist, ids);
                    },
                  ),
                )
              else ...[
                SliverList.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                  itemBuilder: (context, i) => TrackTile(
                    track: tracks[i],
                    playlist: playlist,
                    onTap: () => scope.player.playQueue(tracks, start: i),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(tracksSummary(tracks.length, total), style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
              const BottomSpace(),
            ],
          ),
        );
      },
    );
  }

  static String _updated(DateTime d) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    return switch (days) {
      <= 0 => 'AGGIORNATA OGGI',
      1 => 'AGGIORNATA IERI',
      < 7 => 'AGGIORNATA $days GIORNI FA',
      _ => 'AGGIORNATA IL ${formatDate(d)}',
    };
  }
}
