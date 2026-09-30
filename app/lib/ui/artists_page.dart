import 'package:flutter/material.dart';

import '../models/track.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'theme.dart';
import 'track_tile.dart';
import 'widgets.dart';

const unknownArtist = 'Artista sconosciuto';
const unknownAlbum = 'Album sconosciuto';

String artistOf(Track t) => t.artist.trim().isEmpty ? unknownArtist : t.artist.trim();
String albumOf(Track t) => (t.album ?? '').trim().isEmpty ? unknownAlbum : t.album!.trim();

/// Elenco degli artisti della libreria (nona immagine del mockup).
class ArtistsPage extends StatelessWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final byArtist = <String, List<Track>>{};
        for (final t in scope.library.tracks) {
          byArtist.putIfAbsent(artistOf(t), () => []).add(t);
        }
        final names = byArtist.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return LargeTitlePage(
          title: 'Artisti',
          backLabel: 'Libreria',
          slivers: [
            if (names.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: 'Nessun artista',
                  message: 'Gli artisti dei brani che scarichi compaiono qui.',
                ),
              )
            else
              SliverList.separated(
                itemCount: names.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, i) {
                  final withCover = byArtist[names[i]]!.firstWhere(
                    (t) => t.coverFileName != null || t.thumbnail != null,
                    orElse: () => byArtist[names[i]]!.first,
                  );
                  return ListTile(
                    leading: ClipOval(
                      child: Cover(
                        file: scope.library.coverFile(withCover),
                        url: withCover.thumbnail,
                        size: 44,
                        radius: 0,
                        placeholderIcon: Icons.mic,
                      ),
                    ),
                    title: Text(names[i], style: const TextStyle(fontSize: 18)),
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist: names[i]))),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

enum _AlbumSort { name, year }

/// La pagina di un artista con i suoi album (decima immagine del mockup).
class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.artist});

  final String artist;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  _AlbumSort _sort = _AlbumSort.name;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final name = widget.artist.trim().isEmpty ? unknownArtist : widget.artist.trim();
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final tracks = scope.library.tracks.where((t) => artistOf(t) == name).toList();
        final albums = <String, List<Track>>{};
        for (final t in tracks) {
          albums.putIfAbsent(albumOf(t), () => []).add(t);
        }
        int? yearOf(String album) =>
            albums[album]!.map((t) => t.year).whereType<int>().fold<int?>(null, (a, b) => a ?? b);
        final names = albums.keys.toList()
          ..sort(
            (a, b) => _sort == _AlbumSort.year
                ? (yearOf(b) ?? 0).compareTo(yearOf(a) ?? 0)
                : a.toLowerCase().compareTo(b.toLowerCase()),
          );
        final wide = MediaQuery.sizeOf(context).width;

        return LargeTitlePage(
          title: name,
          backLabel: 'Artisti',
          actions: [
            PopupMenuButton<_AlbumSort>(
              initialValue: _sort,
              color: AppColors.surfaceHigh,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => const [
                PopupMenuItem(value: _AlbumSort.name, child: Text('Titolo')),
                PopupMenuItem(value: _AlbumSort.year, child: Text('Anno di uscita')),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: PlayShuffleRow(
                  onPlay: tracks.isEmpty ? null : () => scope.player.playQueue(tracks),
                  onShuffle: tracks.isEmpty ? null : () => scope.player.playQueue(tracks, shuffle: true),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1, indent: 20)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (wide / 190).floor().clamp(2, 6),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: names.length,
                itemBuilder: (context, i) {
                  final album = names[i];
                  final first = albums[album]!.first;
                  final year = yearOf(album);
                  return LayoutBuilder(
                    builder: (context, c) => CarouselItem(
                      image: Cover.track(scope.library, first, size: c.maxWidth, radius: 6),
                      title: album,
                      subtitle: year?.toString(),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AlbumPage(artist: name, album: album),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// I brani di un album di un artista.
class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key, required this.artist, required this.album});

  final String artist;
  final String album;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final tracks = scope.library.tracks.where((t) => artistOf(t) == artist && albumOf(t) == album).toList();
        return LargeTitlePage(
          title: album,
          backLabel: artist,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: PlayShuffleRow(
                  onPlay: tracks.isEmpty ? null : () => scope.player.playQueue(tracks),
                  onShuffle: tracks.isEmpty ? null : () => scope.player.playQueue(tracks, shuffle: true),
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
        );
      },
    );
  }
}
