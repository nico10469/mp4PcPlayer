import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_manager.dart';
import '../services/server_api.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'theme.dart';

final _youtubeLink = RegExp(r'^https?://([a-z0-9-]+\.)*(youtube\.com|youtu\.be)/', caseSensitive: false);

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _controller = TextEditingController();
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
    // Un link incollato si scarica direttamente, senza ricerca.
    if (_youtubeLink.hasMatch(query)) {
      setState(() => _error = null);
      final track = await downloads.download(query, source: query);
      if (!mounted) return;
      final state = downloads.stateOf(query);
      _snack(track != null ? '"${track.title}" aggiunto alla libreria' : 'Download fallito: ${state?.error}');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await downloads.api.search(query);
      if (mounted) setState(() => _results = results);
    } on ServerException catch (e) {
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
    final scope = AppScope.of(context);
    return CustomScrollView(
      slivers: [
        const SliverAppBar(title: Text('Scarica'), pinned: true),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: 'Artisti, brani o link YouTube',
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, color: AppColors.accent),
                  onPressed: () => _submit(_controller.text),
                ),
              ),
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
                'Cerca un brano o incolla un link: il server lo scarica e lo salva sul dispositivo, '
                'così puoi ascoltarlo anche offline.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ListenableBuilder(
          listenable: Listenable.merge([scope.downloads, scope.library]),
          builder: (context, _) => SliverList.separated(
            itemCount: _loading || _error != null ? 0 : _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, i) {
              final r = _results[i];
              return ListTile(
                leading: Cover(url: r.thumbnail),
                title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${r.artist}  ·  ${formatDuration(r.duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _DownloadButton(
                  state: scope.downloads.stateOf(r.id),
                  inLibrary: scope.library.contains(r.id),
                  onPressed: () async {
                    final track = await scope.downloads.download(r.id);
                    if (!context.mounted) return;
                    final err = scope.downloads.stateOf(r.id)?.error;
                    _snack(track != null ? '"${track.title}" aggiunto alla libreria' : 'Download fallito: $err');
                  },
                ),
              );
            },
          ),
        ),
      ],
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
