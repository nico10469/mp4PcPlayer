import 'package:flutter/material.dart';

import '../models/track.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'theme.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.onGoToDownload});

  final VoidCallback onGoToDownload;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.library, scope.player]),
      builder: (context, _) {
        final all = scope.library.tracks;
        final q = _filter.toLowerCase();
        final tracks = q.isEmpty
            ? all
            : all.where((t) => t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q)).toList();
        final playingId = scope.player.current?.id;

        return CustomScrollView(
          slivers: [
            const SliverAppBar(title: Text('Libreria'), pinned: true),
            if (all.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _Empty(onGoToDownload: widget.onGoToDownload))
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Cerca nella libreria',
                          prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                        ),
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _PillButton(
                              icon: Icons.play_arrow,
                              label: 'Riproduci',
                              onPressed: () => scope.player.playQueue(tracks),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PillButton(
                              icon: Icons.shuffle,
                              label: 'Casuale',
                              onPressed: () => scope.player.playQueue(tracks, shuffle: true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SliverList.separated(
                itemCount: tracks.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                itemBuilder: (context, i) => _TrackRow(
                  track: tracks[i],
                  playing: tracks[i].id == playingId,
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

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.playing, required this.onTap});

  final Track track;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListTile(
      onTap: onTap,
      leading: Cover(file: scope.library.coverFile(track), url: track.thumbnail),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: playing ? AppColors.accent : Colors.white),
      ),
      subtitle: Text(
        '${track.artist}  ·  ${formatDuration(track.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
        color: AppColors.surfaceHigh,
        onSelected: (value) async {
          if (value == 'delete') await scope.library.remove(track);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.accent),
              title: Text('Elimina dal dispositivo', style: TextStyle(color: AppColors.accent)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.surfaceHigh,
        foregroundColor: AppColors.accent,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onGoToDownload});

  final VoidCallback onGoToDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.library_music_outlined, size: 64, color: AppColors.textSecondary),
        const SizedBox(height: 16),
        const Text('La tua libreria è vuota', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('I brani che scarichi compaiono qui.', style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        FilledButton(onPressed: onGoToDownload, child: const Text('Scarica musica')),
      ],
    );
  }
}
