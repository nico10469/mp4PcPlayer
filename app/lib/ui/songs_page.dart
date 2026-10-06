import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'l10n.dart';
import 'theme.dart';
import 'track_tile.dart';
import 'widgets.dart';

/// Tutti i brani della libreria.
class SongsPage extends StatefulWidget {
  const SongsPage({super.key});

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final all = scope.library.tracks;
        final q = _filter.toLowerCase();
        final tracks = q.isEmpty
            ? all
            : all.where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)).toList();
        return LargeTitlePage(
          title: tr('Brani'),
          backLabel: tr('Libreria'),
          slivers: [
            if (all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(title: tr('Nessun brano'), message: tr('I brani che scarichi compaiono qui.')),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      TextField(
                        decoration: InputDecoration(
                          hintText: tr('Cerca nei brani'),
                          prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                        ),
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                      const SizedBox(height: 12),
                      PlayShuffleRow(
                        onPlay: () => scope.player.playQueue(tracks),
                        onShuffle: () => scope.player.playQueue(tracks, shuffle: true),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.separated(
                itemCount: tracks.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                itemBuilder: (context, i) => TrackTile(
                  track: tracks[i],
                  onTap: () => scope.player.playQueue(tracks, start: i),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
