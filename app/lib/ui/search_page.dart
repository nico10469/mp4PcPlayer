import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/music_catalog.dart';
import 'app_scope.dart';
import 'download_page.dart';
import 'theme.dart';
import 'track_tile.dart';
import 'widgets.dart';

/// La ricerca della lente: filtra la libreria mentre scrivi e, con Invio, cerca anche su YouTube.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';
  String? _onlineQuery;
  List<SearchResult> _online = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _searchOnline() async {
    final q = _query.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _onlineQuery = q;
    });
    try {
      final results = await AppScope.of(context).downloads.catalog.search(q);
      if (mounted && _onlineQuery == q) setState(() => _online = results);
    } on CatalogException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static bool _matches(Track t, String q) =>
      [t.title, t.artist, t.album ?? '', t.genre ?? ''].any((s) => s.toLowerCase().contains(q));

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final q = _query.trim().toLowerCase();
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final local = q.isEmpty ? const <Track>[] : scope.library.tracks.where((t) => _matches(t, q)).toList();
        final showOnline = _onlineQuery != null && _onlineQuery!.toLowerCase() == q;
        return LargeTitlePage(
          title: 'Cerca',
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Brani, artisti, album, generi',
                    prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.cancel, color: AppColors.textSecondary),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                  onSubmitted: (_) => _searchOnline(),
                ),
              ),
            ),
            if (q.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Scrivi per cercare nella tua libreria. Premi Invio per cercare anche su YouTube e scaricare.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else ...[
              const SliverToBoxAdapter(child: SectionTitle('Nella tua libreria')),
              if (local.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text('Nessun brano trovato.', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: local.length,
                  itemBuilder: (context, i) => TrackTile(
                    track: local[i],
                    onTap: () => scope.player.playQueue(local, start: i),
                  ),
                ),
              const SliverToBoxAdapter(child: SectionTitle('Su YouTube')),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_error != null && showOnline)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(_error!, style: const TextStyle(color: AppColors.accent)),
                  ),
                )
              else if (showOnline)
                SliverList.builder(
                  itemCount: _online.length,
                  itemBuilder: (context, i) => YoutubeResultTile(result: _online[i]),
                )
              else
                SliverToBoxAdapter(
                  child: ListTile(
                    leading: const Icon(Icons.travel_explore, color: AppColors.accent),
                    title: Text('Cerca "${_query.trim()}" su YouTube', style: const TextStyle(color: AppColors.accent)),
                    onTap: _searchOnline,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
