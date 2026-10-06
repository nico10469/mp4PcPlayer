import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/music_catalog.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'download_page.dart';
import 'l10n.dart';
import 'theme.dart';
import 'track_tile.dart';
import 'widgets.dart';

String get unknownArtist => tr('Artista sconosciuto');
String get unknownAlbum => tr('Album sconosciuto');

/// Gli artisti con cui il brano compare nella sezione Artisti (principali e ospiti).
List<String> artistsOf(Track t) {
  final names = t.artistNames;
  return names.isEmpty ? [unknownArtist] : names;
}

String albumOf(Track t) => (t.album ?? '').trim().isEmpty ? unknownAlbum : t.album!.trim();

bool _sameName(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

/// Elenco degli artisti della libreria (nona immagine del mockup). Un brano con un ospite
/// compare sotto tutti e due gli artisti.
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
          for (final name in artistsOf(t)) {
            final key = byArtist.keys.firstWhere((k) => _sameName(k, name), orElse: () => name);
            byArtist.putIfAbsent(key, () => []).add(t);
          }
        }
        final names = byArtist.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return LargeTitlePage(
          title: tr('Artisti'),
          backLabel: tr('Libreria'),
          slivers: [
            if (names.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: tr('Nessun artista'),
                  message: tr('Gli artisti dei brani che scarichi compaiono qui.'),
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

/// Un album nella pagina dell'artista: dalla discografia di YouTube Music, dalla libreria o da tutte e due.
class _AlbumEntry {
  _AlbumEntry({required this.title, this.year, this.type, this.online, this.local = const []});

  final String title;
  int? year;
  final String? type;

  /// L'album su YouTube Music (null se è solo nella libreria).
  final SearchResult? online;

  /// I brani dell'album già in libreria.
  List<Track> local;
}

/// La pagina di un artista: i 5 brani che ascolti di più e tutti i suoi album.
class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.artist});

  final String artist;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  _AlbumSort _sort = _AlbumSort.year;
  Future<Discography>? _discography;

  String get _name => widget.artist.trim().isEmpty ? unknownArtist : widget.artist.trim();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_discography != null || _name == unknownArtist) return;
    _discography = AppScope.of(context).downloads.discography(_name);
  }

  /// Gli album di YouTube Music, con accanto i brani che hai già; poi gli album che ci sono
  /// solo nella libreria (importati, scritti a mano...).
  List<_AlbumEntry> _albums(List<Track> tracks, List<SearchResult> online) {
    final local = <String, List<Track>>{};
    for (final t in tracks) {
      local.putIfAbsent(albumOf(t), () => []).add(t);
    }
    final entries = <_AlbumEntry>[
      for (final a in online) _AlbumEntry(title: a.title, year: a.year, type: a.type, online: a),
    ];
    for (final MapEntry(key: title, value: songs) in local.entries) {
      final match = entries.where((e) => _sameName(e.title, title)).firstOrNull;
      if (match != null) {
        match.local = songs;
      } else {
        final year = songs.map((t) => t.year).whereType<int>().firstOrNull;
        entries.add(_AlbumEntry(title: title, year: year, local: songs));
      }
    }
    entries.sort(
      (a, b) => _sort == _AlbumSort.year
          ? (b.year ?? 0).compareTo(a.year ?? 0)
          : a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final name = _name;
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final tracks = scope.library.tracks.where((t) => artistsOf(t).any((a) => _sameName(a, name))).toList();
        final top = [...tracks]
          ..sort((a, b) {
            final byPlays = scope.library.playCount(b.id).compareTo(scope.library.playCount(a.id));
            return byPlays != 0 ? byPlays : b.addedAt.compareTo(a.addedAt);
          });

        return LargeTitlePage(
          title: name,
          backLabel: tr('Artisti'),
          actions: [
            PopupMenuButton<_AlbumSort>(
              initialValue: _sort,
              color: AppColors.surfaceHigh,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => [
                PopupMenuItem(value: _AlbumSort.name, child: Text(tr('Titolo'))),
                PopupMenuItem(value: _AlbumSort.year, child: Text(tr('Anno di uscita'))),
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: PlayShuffleRow(
                  onPlay: tracks.isEmpty ? null : () => scope.player.playQueue(top),
                  onShuffle: tracks.isEmpty ? null : () => scope.player.playQueue(tracks, shuffle: true),
                ),
              ),
            ),
            if (top.isNotEmpty) ...[
              SliverToBoxAdapter(child: SectionTitle(tr('I più ascoltati'))),
              SliverList.list(
                children: [
                  for (var i = 0; i < top.length && i < 5; i++)
                    _TopTrackTile(
                      rank: i + 1,
                      track: top[i],
                      plays: scope.library.playCount(top[i].id),
                      onTap: () => scope.player.playQueue(top, start: i),
                    ),
                ],
              ),
            ],
            FutureBuilder<Discography>(
              future: _discography,
              builder: (context, snap) {
                final online = snap.data;
                final albums = _albums(tracks, online?.albums ?? const []);
                final singles = online?.singles ?? const <SearchResult>[];
                final loading = _discography != null && snap.connectionState != ConnectionState.done;
                return SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: SectionTitle(
                        tr('Album'),
                        trailing: loading
                            ? const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            : null,
                      ),
                    ),
                    if (snap.hasError)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Text(
                            tr(
                              'Non riesco a leggere la discografia completa adesso: ecco gli album che hai in libreria.',
                            ),
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ),
                      ),
                    _AlbumGrid(artist: name, albums: albums),
                    if (singles.isNotEmpty) ...[
                      SliverToBoxAdapter(child: SectionTitle(tr('Singoli ed EP'))),
                      _AlbumGrid(artist: name, albums: _albums(const [], singles), placeholder: Icons.music_note),
                    ],
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// Un brano tra i più ascoltati: posizione, copertina, titolo e quante volte l'hai ascoltato.
class _TopTrackTile extends StatelessWidget {
  const _TopTrackTile({required this.rank, required this.track, required this.plays, required this.onTap});

  final int rank;
  final Track track;
  final int plays;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 4, 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: const TextStyle(color: AppColors.accent, fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            Cover.track(scope.library, track),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    albumOf(track),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$plays', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text(
                  plays == 1 ? tr('riproduzione') : tr('riproduzioni'),
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
            TrackMenuButton(track: track),
          ],
        ),
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.artist, required this.albums, this.placeholder = Icons.album});

  final String artist;
  final List<_AlbumEntry> albums;
  final IconData placeholder;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width;
    if (albums.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(tr('Nessun album'), style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (wide / 190).floor().clamp(2, 6),
          crossAxisSpacing: 16,
          mainAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        itemCount: albums.length,
        itemBuilder: (context, i) {
          final a = albums[i];
          final first = a.local.firstOrNull;
          final details = [
            if (a.year != null) '${a.year}',
            if (a.local.isNotEmpty) tr('In libreria') else if (a.type != null && a.type != 'Album') a.type!,
          ];
          return LayoutBuilder(
            builder: (context, c) => CarouselItem(
              image: first != null
                  ? Cover.track(scope.library, first, size: c.maxWidth, radius: 6)
                  : Cover(url: a.online?.thumbnail, size: c.maxWidth, radius: 6, placeholderIcon: placeholder),
              title: a.title,
              subtitle: details.isEmpty ? null : details.join(' · '),
              // Gli album che hai già si aprono dalla libreria; gli altri si possono scaricare.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => a.local.isNotEmpty || a.online == null
                      ? AlbumPage(artist: artist, album: first != null ? albumOf(first) : a.title)
                      : CollectionPage(source: a.online!.id, preview: a.online),
                ),
              ),
            ),
          );
        },
      ),
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
        final tracks = scope.library.tracks
            .where((t) => artistsOf(t).any((a) => _sameName(a, artist)) && albumOf(t) == album)
            .toList();
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
