import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'app_scope.dart';
import 'artists_page.dart';
import 'cover.dart';
import 'playlist_editor.dart';
import 'theme.dart';
import 'track_info_sheet.dart';

/// Riga di un brano: copertina, titolo, artista, preferito e menu "…".
class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, required this.onTap, this.playlist});

  final Track track;
  final VoidCallback onTap;

  /// La playlist in cui si trova la riga, per offrire "Rimuovi dalla playlist".
  final Playlist? playlist;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.player, scope.playlists]),
      builder: (context, _) {
        final playing = scope.player.current?.id == track.id;
        return ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          leading: Cover.track(scope.library, track),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: playing ? AppColors.accent : Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [track.artist, formatDuration(track.duration)].where((s) => s.isNotEmpty).join('  ·  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (scope.playlists.isFavorite(track))
                const Icon(Icons.favorite, size: 16, color: AppColors.accent, semanticLabel: 'Preferito'),
              TrackMenuButton(track: track, playlist: playlist),
            ],
          ),
        );
      },
    );
  }
}

enum _TrackAction { removeFromPlaylist, delete, addToPlaylist, playNext, showArtist, favorite, info }

/// Il menu "…" di un brano (ottava immagine del mockup).
class TrackMenuButton extends StatelessWidget {
  const TrackMenuButton({super.key, required this.track, this.playlist, this.color = Colors.white});

  final Track track;
  final Playlist? playlist;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final favorite = scope.playlists.isFavorite(track);

    PopupMenuItem<_TrackAction> item(_TrackAction value, String label, IconData icon, {bool danger = false}) {
      final c = danger ? AppColors.accent : Colors.white;
      return PopupMenuItem(
        value: value,
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: c, fontSize: 16)),
            ),
            const SizedBox(width: 16),
            Icon(icon, color: c, size: 22),
          ],
        ),
      );
    }

    return PopupMenuButton<_TrackAction>(
      tooltip: 'Altre azioni',
      icon: Icon(Icons.more_horiz, color: color),
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      constraints: const BoxConstraints(minWidth: 240),
      onSelected: (action) => _run(context, action),
      itemBuilder: (_) => [
        if (playlist != null)
          item(_TrackAction.removeFromPlaylist, 'Rimuovi dalla playlist', Icons.remove_circle, danger: true),
        item(_TrackAction.delete, 'Elimina dalla libreria', Icons.delete, danger: true),
        const PopupMenuDivider(height: 6),
        item(_TrackAction.addToPlaylist, 'Aggiungi a playlist…', Icons.playlist_add),
        item(_TrackAction.playNext, 'Riproduci dopo', Icons.queue_play_next),
        item(_TrackAction.showArtist, 'Mostra artista', Icons.mic_external_on),
        item(
          _TrackAction.favorite,
          favorite ? 'Togli dai preferiti' : 'Preferito',
          favorite ? Icons.heart_broken : Icons.favorite,
        ),
        item(_TrackAction.info, 'Info brano', Icons.info_outline),
      ],
    );
  }

  Future<void> _run(BuildContext context, _TrackAction action) async {
    final scope = AppScope.of(context);
    switch (action) {
      case _TrackAction.removeFromPlaylist:
        await scope.playlists.removeTrack(playlist!, track.id);
      case _TrackAction.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surfaceHigh,
            title: const Text('Eliminare il brano?'),
            content: Text('"${track.title}" verrà cancellato da questo dispositivo e da tutte le playlist.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Elimina')),
            ],
          ),
        );
        if (ok == true) await scope.library.remove(track);
      case _TrackAction.addToPlaylist:
        await showAddToPlaylist(context, [track.id]);
      case _TrackAction.playNext:
        await scope.player.playNext(track);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${track.title}" sarà il prossimo'), behavior: SnackBarBehavior.floating),
          );
        }
      case _TrackAction.showArtist:
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist: track.artist)));
      case _TrackAction.favorite:
        await scope.playlists.toggleFavorite(track);
      case _TrackAction.info:
        await showTrackInfo(context, track);
    }
  }
}

/// Scheda per scegliere a quale playlist aggiungere i brani [ids] (o crearne una nuova).
Future<void> showAddToPlaylist(BuildContext context, List<String> ids) {
  final scope = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheetContext) {
      final playlists = scope.playlists.playlists;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Aggiungi a playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.add_box, color: AppColors.accent, size: 36),
              title: const Text('Nuova playlist…', style: TextStyle(color: AppColors.accent)),
              onTap: () {
                Navigator.pop(sheetContext);
                showPlaylistEditor(context, initialTrackIds: ids);
              },
            ),
            for (final p in playlists)
              ListTile(
                leading: PlaylistCover(playlist: p, size: 40),
                title: Text(p.name),
                subtitle: Text(p.trackIds.length == 1 ? '1 brano' : '${p.trackIds.length} brani'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await scope.playlists.addTracks(p, ids);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Aggiunto a "${p.name}"'), behavior: SnackBarBehavior.floating),
                    );
                  }
                },
              ),
          ],
        ),
      );
    },
  );
}
