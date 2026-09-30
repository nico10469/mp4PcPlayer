import 'package:flutter/material.dart';

import '../models/track.dart';
import 'app_scope.dart';
import 'theme.dart';
import 'track_tile.dart';
import 'widgets.dart';

/// La copertina dei Preferiti: cuore viola su sfondo lilla.
class FavoritesCover extends StatelessWidget {
  const FavoritesCover({super.key, this.size = 80, this.radius = 6});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8DAFB), AppColors.favoriteBackground],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.favorite, color: AppColors.favorite, size: size * 0.5, semanticLabel: 'Preferiti'),
    );
  }
}

void openFavorites(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FavoritesPage()));
}

/// La cartella speciale dei brani con il "mi piace". I file restano dove sono:
/// qui c'è solo l'elenco, dall'ultimo aggiunto.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.playlists, scope.library]),
      builder: (context, _) {
        final tracks = scope.playlists.favoriteTracks;
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
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    children: [
                      const FavoritesCover(size: 220, radius: 10),
                      const SizedBox(height: 20),
                      const Text('Preferiti', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
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
                const SliverToBoxAdapter(
                  child: EmptyState(
                    title: 'Ancora nessun preferito',
                    message: 'Tocca il cuore mentre ascolti un brano, o scegli "Mi piace" dal menu "…".',
                  ),
                )
              else ...[
                SliverList.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                  itemBuilder: (context, i) => TrackTile(
                    track: tracks[i],
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
}

/// Il cuore del "mi piace": pieno e viola quando il brano è tra i preferiti.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.track, this.color = Colors.white, this.size = 26});

  final Track track;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.playlists,
      builder: (context, _) {
        final on = scope.playlists.isFavorite(track);
        return IconButton(
          tooltip: on ? 'Non mi piace più' : 'Mi piace',
          iconSize: size,
          icon: Icon(on ? Icons.favorite : Icons.favorite_border, color: on ? AppColors.favoriteOnDark : color),
          onPressed: () => scope.playlists.toggleFavorite(track),
        );
      },
    );
  }
}
