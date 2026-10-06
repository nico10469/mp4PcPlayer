import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'artists_page.dart';
import 'cover.dart';
import 'download_page.dart';
import 'favorites.dart';
import 'l10n.dart';
import 'playlist_editor.dart';
import 'playlists_page.dart';
import 'settings_page.dart';
import 'songs_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// La Libreria (prima immagine del mockup): le voci principali e, sotto,
/// le copertine degli aggiunti di recente e delle playlist (layout della seconda immagine).
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final rows = librarySections();

    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([scope.library, scope.playlists]),
        builder: (context, _) {
          final tracks = scope.library.tracks;
          final recent = tracks.take(20).toList();
          final favorites = scope.playlists.favoriteTracks;
          final playlists = scope.playlists.playlists;

          return CustomScrollView(
            slivers: [
              const SliverAppBar(pinned: true, toolbarHeight: 48),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Libreria'),
                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const AppLogo(size: 40),
                    ],
                  ),
                ),
              ),
              SliverList.list(
                children: [
                  for (final r in rows) _LibraryRow(icon: r.icon, label: r.label, onTap: () => _push(context, r.page)),
                ],
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
              if (tracks.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(
                    title: tr('La tua libreria è vuota'),
                    message: tr('I brani che scarichi compaiono qui.'),
                    action: tr('Scarica musica'),
                    onAction: () => _push(context, const DownloadPage()),
                  ),
                )
              else ...[
                SliverToBoxAdapter(child: SectionTitle(tr('Aggiunti di recente'))),
                SliverToBoxAdapter(
                  child: CoverCarousel(
                    itemCount: recent.length,
                    itemBuilder: (context, i) => CarouselItem(
                      image: Cover.track(scope.library, recent[i], size: 150, radius: 6),
                      title: recent[i].title,
                      subtitle: recent[i].artist,
                      onTap: () => scope.player.playQueue(recent, start: i),
                    ),
                  ),
                ),
                if (favorites.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: SectionTitle(
                      tr('Preferiti'),
                      trailing: TextAction(label: tr('Vedi tutti'), onPressed: () => openFavorites(context)),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: CoverCarousel(
                      itemCount: favorites.length,
                      itemBuilder: (context, i) => CarouselItem(
                        image: Cover.track(scope.library, favorites[i], size: 150, radius: 6),
                        title: favorites[i].title,
                        subtitle: favorites[i].artist,
                        onTap: () => scope.player.playQueue(favorites, start: i),
                      ),
                    ),
                  ),
                ],
              ],
              SliverToBoxAdapter(
                child: SectionTitle(
                  tr('Playlist'),
                  trailing: playlists.isEmpty
                      ? null
                      : TextAction(label: tr('Vedi tutte'), onPressed: () => _push(context, const PlaylistsPage())),
                ),
              ),
              SliverToBoxAdapter(
                child: CoverCarousel(
                  itemCount: playlists.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 1) {
                      final n = favorites.length;
                      return CarouselItem(
                        image: const FavoritesCover(size: 150),
                        title: tr('Preferiti'),
                        subtitle: plural(n, '1 brano', '{n} brani'),
                        onTap: () => openFavorites(context),
                      );
                    }
                    if (i == 0) {
                      return CarouselItem(
                        image: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.add, color: AppColors.accent, size: 48),
                        ),
                        title: tr('Nuova playlist'),
                        subtitle: tr('Crea'),
                        onTap: () async {
                          final created = await showPlaylistEditor(context);
                          if (created != null && context.mounted) openPlaylist(context, created);
                        },
                      );
                    }
                    final p = playlists[i - 2];
                    return CarouselItem(
                      image: PlaylistCover(playlist: p, size: 150),
                      title: p.name,
                      subtitle: plural(p.trackIds.length, '1 brano', '{n} brani'),
                      onTap: () => openPlaylist(context, p),
                    );
                  },
                ),
              ),
              const BottomSpace(),
            ],
          );
        },
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  const _LibraryRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500)),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSecondary),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le voci della Libreria (e della barra laterale sul computer).
List<({IconData icon, String label, Widget page})> librarySections() => [
  (icon: Icons.queue_music, label: tr('Playlist'), page: const PlaylistsPage()),
  (icon: Icons.mic, label: tr('Artisti'), page: const ArtistsPage()),
  (icon: Icons.music_note, label: tr('Brani'), page: const SongsPage()),
  (icon: Icons.arrow_circle_down, label: tr('Download'), page: const DownloadPage()),
  (icon: Icons.settings, label: tr('Impostazioni'), page: const SettingsPage()),
];
