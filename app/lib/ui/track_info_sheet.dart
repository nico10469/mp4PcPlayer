import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/track.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'theme.dart';
import 'widgets.dart';

/// Scheda con i metadati del brano (copertina, titolo, artista, album, genere, anno, testo...)
/// e la possibilità di modificarli.
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
  bool _started = false;
  bool _searchingLyrics = false;
  String? _lyricsError;
  final _fields = {
    for (final k in ['title', 'artist', 'album', 'albumArtist', 'genre', 'year', 'lyrics']) k: TextEditingController(),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final scope = AppScope.of(context);
    final file = scope.library.audioFile(widget.fallback);
    file.length().then((v) => mounted ? setState(() => _size = v) : null, onError: (_) {});
    // Il testo si cerca da solo la prima volta che si aprono le info del brano.
    if (_track(scope).lyrics == null) _findLyrics();
  }

  Future<void> _findLyrics() async {
    final scope = AppScope.of(context);
    setState(() {
      _searchingLyrics = true;
      _lyricsError = null;
    });
    try {
      final text = await scope.lyrics.find(_track(scope));
      final current = _track(scope);
      // Un testo scritto a mano nel frattempo non si sovrascrive.
      if (current.lyrics == null || current.lyrics!.isEmpty) await scope.library.update(current.copyWith(lyrics: text));
    } catch (_) {
      _lyricsError = 'Non riesco a raggiungere LRCLIB: controlla la connessione a internet.';
    } finally {
      if (mounted) setState(() => _searchingLyrics = false);
    }
  }

  Future<void> _changeCover(AppScope scope, Track t) async {
    final picked = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Scegli la copertina');
    final path = picked?.path;
    if (path != null) await scope.library.setCover(t, File(path));
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
    _fields['lyrics']!.text = t.lyrics ?? '';
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
        lyrics: _fields['lyrics']!.text,
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
                if (_editing)
                  Tooltip(
                    message: 'Cambia copertina',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _changeCover(scope, t),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Cover.track(scope.library, t, size: 72, radius: 8),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0x88000000),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.photo_camera, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  )
                else
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
            if (_editing) ..._editor(scope, t) else ...[..._details(t), ..._lyrics(t)],
          ],
        );
      },
    );
  }

  List<Widget> _editor(AppScope scope, Track t) {
    Widget field(String key, String label, {bool number = false, bool multiline = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _fields[key],
        keyboardType: number
            ? TextInputType.number
            : multiline
            ? TextInputType.multiline
            : TextInputType.text,
        minLines: multiline ? 4 : 1,
        maxLines: multiline ? 12 : 1,
        inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)] : null,
        decoration: InputDecoration(labelText: label, alignLabelWithHint: multiline),
      ),
    );
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.accent),
          onPressed: () => _changeCover(scope, t),
          icon: const Icon(Icons.image),
          label: const Text('Cambia copertina'),
        ),
      ),
      const SizedBox(height: 8),
      field('title', 'Titolo'),
      field('artist', 'Artista'),
      field('album', 'Album'),
      field('albumArtist', 'Artista dell\'album'),
      field('genre', 'Genere'),
      field('year', 'Anno', number: true),
      field('lyrics', 'Testo', multiline: true),
    ];
  }

  List<Widget> _lyrics(Track t) {
    final text = t.lyrics;
    Widget body;
    if (_searchingLyrics) {
      body = const Row(
        children: [
          SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Cerco il testo…', style: TextStyle(color: AppColors.textSecondary)),
        ],
      );
    } else if (text != null && text.isNotEmpty) {
      body = SelectableText(text, style: const TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w600));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _lyricsError ?? (text == null ? 'Testo non ancora cercato.' : 'Testo non trovato (o brano strumentale).'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: EdgeInsets.zero),
            onPressed: _findLyrics,
            child: const Text('Cerca di nuovo'),
          ),
        ],
      );
    }
    return [
      const SizedBox(height: 24),
      const Text('TESTO', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      const SizedBox(height: 10),
      body,
      if (text != null && text.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text(
          'Testo in lingua originale da LRCLIB o dai tag del file. Puoi correggerlo con Modifica.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
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
