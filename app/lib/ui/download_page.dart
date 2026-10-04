import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_manager.dart';
import '../services/music_catalog.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'theme.dart';
import 'widgets.dart';

final _youtubeLink = RegExp(r'^https?://([a-z0-9-]+\.)*(youtube\.com|youtu\.be)/', caseSensitive: false);

/// Un link a una playlist o a un album (list=... oppure /browse/MPREb...).
bool isCollectionLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.queryParameters.containsKey('list') || uri.path.startsWith('/browse/');
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _controller = TextEditingController();
  ResultKind _kind = ResultKind.song;
  String _query = '';
  List<SearchResult> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;
    final downloads = AppScope.of(context).downloads;
    if (_youtubeLink.hasMatch(query)) {
      setState(() => _error = null);
      // Un link a un album o a una playlist apre l'elenco dei brani.
      if (isCollectionLink(query)) {
        openCollection(context, query);
        return;
      }
      // Il link di un brano si scarica direttamente, senza ricerca.
      final track = await downloads.download(query, source: query);
      if (!mounted) return;
      final state = downloads.stateOf(query);
      _snack(track != null ? '"${track.title}" aggiunto alla libreria' : 'Download fallito: ${state?.error}');
      return;
    }
    _query = query;
    await _search();
  }

  Future<void> _search() async {
    if (_query.isEmpty) return;
    final downloads = AppScope.of(context).downloads;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await downloads.catalog.search(_query, kind: _kind);
      if (mounted) setState(() => _results = results);
    } on CatalogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return LargeTitlePage(
      title: 'Scarica musica',
      backLabel: 'Libreria',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: 'Brani, album, playlist o link YouTube',
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: AppColors.accent),
                  onPressed: () => _submit(_controller.text),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<ResultKind>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.accent,
                selectedForegroundColor: Colors.white,
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.divider),
              ),
              segments: const [
                ButtonSegment(value: ResultKind.song, label: Text('Brani')),
                ButtonSegment(value: ResultKind.album, label: Text('Album')),
                ButtonSegment(value: ResultKind.playlist, label: Text('Playlist')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) {
                setState(() {
                  _kind = s.first;
                  _results = const [];
                });
                _search();
              },
            ),
          ),
        ),
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: AppColors.accent)),
            ),
          )
        else if (_results.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Cerca su YouTube Music: trovi i brani ufficiali (solo audio, con la copertina dell\'album), '
                'gli album e le playlist da scaricare interi. Puoi anche incollare un link.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          )
        else
          SliverList.separated(
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, i) {
              final r = _results[i];
              return r.kind == ResultKind.song ? YoutubeResultTile(result: r) : CollectionResultTile(result: r);
            },
          ),
      ],
    );
  }
}

/// Un brano di YouTube Music con il pulsante per scaricarlo.
class YoutubeResultTile extends StatelessWidget {
  const YoutubeResultTile({super.key, required this.result, this.album, this.albumArtist, this.fallbackCover});

  final SearchResult result;

  /// Album e copertina della raccolta da cui viene il brano, se c'è.
  final String? album;
  final String? albumArtist;
  final String? fallbackCover;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final r = result;
    final details = [r.artist, if (r.album != null && r.album != album) r.album!, formatDuration(r.duration)];
    return ListenableBuilder(
      listenable: Listenable.merge([scope.downloads, scope.library]),
      builder: (context, _) => ListTile(
        leading: Cover(url: r.thumbnail ?? fallbackCover),
        title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(details.where((s) => s.isNotEmpty).join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: _DownloadButton(
          state: scope.downloads.stateOf(r.id),
          inLibrary: scope.library.contains(r.id),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final track = await scope.downloads.download(
              r.id,
              result: r,
              cover: r.thumbnail ?? fallbackCover,
              album: album ?? r.album,
              albumArtist: albumArtist,
            );
            final err = scope.downloads.stateOf(r.id)?.error;
            messenger.showSnackBar(
              SnackBar(
                content: Text(track != null ? '"${track.title}" aggiunto alla libreria' : 'Download fallito: $err'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Un album o una playlist: toccandolo si vedono i brani e si scaricano tutti insieme.
class CollectionResultTile extends StatelessWidget {
  const CollectionResultTile({super.key, required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final details = [
      if (r.kind == ResultKind.album) r.type ?? 'Album' else 'Playlist',
      r.artist,
      if (r.year != null) '${r.year}',
      if (r.count != null) '${r.count} brani',
    ];
    return ListTile(
      leading: Cover(url: r.thumbnail, placeholderIcon: r.kind == ResultKind.album ? Icons.album : Icons.queue_music),
      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details.where((s) => s.isNotEmpty).join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: () => openCollection(context, r.id, preview: r),
    );
  }
}

void openCollection(BuildContext context, String source, {SearchResult? preview}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CollectionPage(source: source, preview: preview),
    ),
  );
}

/// I brani di un album o di una playlist di YouTube, con "Scarica tutto".
class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, required this.source, this.preview});

  /// Id o link dell'album / playlist.
  final String source;

  /// Il risultato della ricerca, per mostrare subito titolo e copertina.
  final SearchResult? preview;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late Future<Collection> _future;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = AppScope.of(context).downloads.catalog.collection(widget.source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Collection>(
        future: _future,
        builder: (context, snap) {
          final c = snap.data;
          final title = c?.title ?? widget.preview?.title ?? '';
          final artist = c?.artist ?? widget.preview?.artist ?? '';
          final cover = c?.thumbnail ?? widget.preview?.thumbnail;
          return CustomScrollView(
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
                      Cover(url: cover, size: 220, radius: 10, placeholderIcon: Icons.album),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                      ),
                      if (artist.isNotEmpty)
                        Text(artist, style: const TextStyle(fontSize: 18, color: AppColors.accent)),
                      const SizedBox(height: 16),
                      if (c != null) _DownloadAll(collection: c),
                    ],
                  ),
                ),
              ),
              if (snap.hasError)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      snap.error is CatalogException ? (snap.error as CatalogException).message : '${snap.error}',
                      style: const TextStyle(color: AppColors.accent),
                    ),
                  ),
                )
              else if (c == null)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: c.tracks.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                  itemBuilder: (context, i) => YoutubeResultTile(
                    result: c.tracks[i],
                    album: c.kind == ResultKind.album ? c.title : null,
                    albumArtist: c.kind == ResultKind.album && c.artist.isNotEmpty ? c.artist : null,
                    fallbackCover: c.thumbnail,
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

class _DownloadAll extends StatelessWidget {
  const _DownloadAll({required this.collection});

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final c = collection;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.downloads, scope.library]),
      builder: (context, _) {
        final progress = scope.downloads.collectionState(c.id);
        final missing = c.tracks.where((t) => !scope.library.contains(t.id)).length;
        final running = progress?.running ?? false;
        String label;
        if (running) {
          label = 'Scaricati ${progress!.done} di ${progress.total}…';
        } else if (c.tracks.isEmpty) {
          label = 'Nessun brano disponibile';
        } else if (missing == 0) {
          label = 'Tutti i brani sono in libreria';
        } else {
          label = missing == c.tracks.length ? 'Scarica tutto (${c.tracks.length})' : 'Scarica i $missing mancanti';
        }
        return Column(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(240, 46)),
              onPressed: running || missing == 0
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await scope.downloads.downloadCollection(c);
                      final p = scope.downloads.collectionState(c.id);
                      messenger.showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            [
                              c.kind == ResultKind.playlist
                                  ? 'Playlist "${c.title}" salvata'
                                  : '"${c.title}" scaricato',
                              if ((p?.failed ?? 0) > 0) '${p!.failed} brani non disponibili',
                            ].join(' · '),
                          ),
                        ),
                      );
                    },
              icon: running
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download),
              label: Text(label),
            ),
            if (running) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress!.total == 0 ? null : (progress.done + progress.failed) / progress.total,
                backgroundColor: AppColors.surfaceHigh,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.state, required this.inLibrary, required this.onPressed});

  final DownloadState? state;
  final bool inLibrary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final phase = state?.phase;
    if (phase == DownloadPhase.server || phase == DownloadPhase.transfer) {
      return SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          value: state!.progress == 0 ? null : state!.progress,
          strokeWidth: 3,
          backgroundColor: AppColors.surfaceHigh,
        ),
      );
    }
    if (inLibrary) {
      return const Icon(Icons.check_circle, color: AppColors.accent, semanticLabel: 'Già scaricato');
    }
    return IconButton(
      tooltip: phase == DownloadPhase.error ? 'Riprova' : 'Scarica',
      icon: Icon(
        phase == DownloadPhase.error ? Icons.refresh : Icons.download_for_offline_outlined,
        color: AppColors.accent,
      ),
      onPressed: onPressed,
    );
  }
}
