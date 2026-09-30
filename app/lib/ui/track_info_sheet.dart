import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'theme.dart';
import 'widgets.dart';

/// Scheda con i metadati del brano (artista, album, genere, anno...) e la possibilità di modificarli.
Future<void> showTrackInfo(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => _TrackInfo(trackId: track.id, fallback: track, scroll: scroll),
    ),
  );
}

class _TrackInfo extends StatefulWidget {
  const _TrackInfo({required this.trackId, required this.fallback, required this.scroll});

  final String trackId;
  final Track fallback;
  final ScrollController scroll;

  @override
  State<_TrackInfo> createState() => _TrackInfoState();
}

class _TrackInfoState extends State<_TrackInfo> {
  bool _editing = false;
  int? _size;
  final _fields = {
    for (final k in ['title', 'artist', 'album', 'albumArtist', 'genre', 'year']) k: TextEditingController(),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_size != null) return;
    final scope = AppScope.of(context);
    final file = scope.library.audioFile(widget.fallback);
    file.length().then((v) => mounted ? setState(() => _size = v) : null, onError: (_) {});
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Track _track(AppScope scope) {
    for (final t in scope.library.tracks) {
      if (t.id == widget.trackId) return t;
    }
    return widget.fallback;
  }

  void _startEditing(Track t) {
    _fields['title']!.text = t.title;
    _fields['artist']!.text = t.artist;
    _fields['album']!.text = t.album ?? '';
    _fields['albumArtist']!.text = t.albumArtist ?? '';
    _fields['genre']!.text = t.genre ?? '';
    _fields['year']!.text = t.year?.toString() ?? '';
    setState(() => _editing = true);
  }

  Future<void> _save(AppScope scope, Track t) async {
    await scope.library.update(
      t.withMetadata(
        title: _fields['title']!.text,
        artist: _fields['artist']!.text,
        album: _fields['album']!.text,
        albumArtist: _fields['albumArtist']!.text,
        genre: _fields['genre']!.text,
        year: int.tryParse(_fields['year']!.text.trim()),
      ),
    );
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.library,
      builder: (context, _) {
        final t = _track(scope);
        return ListView(
          controller: widget.scroll,
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.paddingOf(context).bottom + 24),
          children: [
            Row(
              children: [
                Cover.track(scope.library, t, size: 72, radius: 8),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(t.artist, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (_editing)
                  TextAction(label: 'Fine', onPressed: () => _save(scope, t))
                else
                  TextAction(label: 'Modifica', onPressed: () => _startEditing(t)),
              ],
            ),
            const SizedBox(height: 16),
            if (_editing) ..._editor() else ..._details(t),
          ],
        );
      },
    );
  }

  List<Widget> _editor() {
    Widget field(String key, String label, {bool number = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _fields[key],
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)] : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return [
      field('title', 'Titolo'),
      field('artist', 'Artista'),
      field('album', 'Album'),
      field('albumArtist', 'Artista dell\'album'),
      field('genre', 'Genere'),
      field('year', 'Anno', number: true),
    ];
  }

  List<Widget> _details(Track t) {
    final rows = <(String, String?)>[
      ('Artista', t.artist.isEmpty ? null : t.artist),
      ('Album', t.album),
      ('Artista dell\'album', t.albumArtist),
      ('Genere', t.genre),
      ('Anno', t.year?.toString()),
      ('Durata', t.duration == null ? null : formatDuration(t.duration)),
      ('Formato', t.format.isEmpty ? null : t.format.toUpperCase()),
      ('Dimensione', _size == null ? null : '${(_size! / (1024 * 1024)).toStringAsFixed(1)} MB'),
      ('Aggiunto il', formatDate(t.addedAt)),
      ('Fonte', t.sourceUrl),
    ];
    return [
      for (final (label, value) in rows) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(label, style: const TextStyle(color: AppColors.textSecondary)),
              ),
              Expanded(
                child: SelectableText(
                  value ?? 'Non disponibile',
                  style: TextStyle(color: value == null ? AppColors.textSecondary : Colors.white),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
      const SizedBox(height: 12),
      const Text(
        'I dati arrivano da YouTube tramite yt-dlp. Se qualcosa manca o è sbagliato, tocca Modifica.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    ];
  }
}
