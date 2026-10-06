import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../services/playlist_store.dart';
import 'app_scope.dart';
import 'favorites.dart';
import 'l10n.dart';
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
          title: tr('Playlist'),
          backLabel: tr('Libreria'),
          actions: [
            PopupMenuButton<PlaylistSort>(
              initialValue: _sort,
              color: AppColors.surfaceHigh,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => [
                PopupMenuItem(value: PlaylistSort.recent, child: Text(tr('Modificate di recente'))),
                PopupMenuItem(value: PlaylistSort.name, child: Text(tr('Nome'))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  tr('Ordina'),
                  style: const TextStyle(color: AppColors.accent, fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          slivers: [
            if (all.isEmpty) ...[
              SliverToBoxAdapter(child: _favoritesRow(context)),
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: tr('Cerchi le tue playlist?'),
                  message: tr('Le playlist che crei compaiono qui.'),
                  action: tr('Nuova playlist'),
                  onAction: _create,
                ),
              ),
            ] else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: tr('Cerca nelle playlist'),
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
                  title: Text(tr('Nuova playlist…'), style: const TextStyle(color: AppColors.accent, fontSize: 18)),
                  onTap: _create,
                ),
              ),
              if (q.isEmpty || tr('Preferiti').toLowerCase().contains(q))
                SliverToBoxAdapter(child: _favoritesRow(context)),
              SliverList.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) => _PlaylistRow(
                  cover: PlaylistCover(playlist: shown[i]),
                  title: Text(shown[i].name, style: const TextStyle(fontSize: 18)),
                  subtitle: plural(shown[i].trackIds.length, '1 brano', '{n} brani'),
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

Widget _favoritesRow(BuildContext context) {
  final count = AppScope.of(context).playlists.favoriteTracks.length;
  return _PlaylistRow(
    cover: const FavoritesCover(),
    title: Text(tr('Preferiti'), style: const TextStyle(fontSize: 18)),
    subtitle: plural(count, '1 brano', '{n} brani'),
    chevron: true,
    onTap: () => openFavorites(context),
  );
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
                decoration: BoxDecoration(
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
                            Text(subtitle!, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (chevron) Icon(Icons.chevron_right, color: AppColors.textSecondary),
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
                    tooltip: tr('Opzioni playlist'),
                    color: AppColors.surfaceHigh,
                    icon: Container(
                      decoration: BoxDecoration(color: AppColors.surfaceHigh, shape: BoxShape.circle),
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
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'edit', child: Text(tr('Modifica'))),
                      PopupMenuItem(value: 'add', child: Text(tr('Aggiungi musica'))),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(tr('Elimina playlist'), style: const TextStyle(color: AppColors.accent)),
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
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary, letterSpacing: 0.5),
                      ),
                      if (playlist.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          playlist.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
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
                    title: tr('Playlist vuota'),
                    message: tr('Aggiungi brani dalla tua libreria.'),
                    action: tr('Aggiungi musica'),
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
      <= 0 => tr('AGGIORNATA OGGI'),
      1 => tr('AGGIORNATA IERI'),
      < 7 => tr('AGGIORNATA {n} GIORNI FA', {'n': days}),
      _ => tr('AGGIORNATA IL {date}', {'date': formatDate(d)}),
    };
  }
}
