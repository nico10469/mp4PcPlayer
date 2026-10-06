import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/server_api.dart';
import '../services/settings.dart';
import '../services/storage_access.dart';
import '../services/ytdlp_audio.dart';
import 'app_scope.dart';
import 'l10n.dart';
import 'playback_settings.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _url = TextEditingController();
  final _token = TextEditingController();
  bool _filled = false;
  String? _status;
  bool _ok = false;
  bool _testing = false;
  bool _moving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final settings = AppScope.of(context).settings;
    _url.text = settings.serverUrl;
    _token.text = settings.token;
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final scope = AppScope.of(context);
    setState(() {
      _testing = true;
      _status = null;
    });
    await scope.settings.save(serverUrl: _url.text, token: _token.text);
    try {
      final version = await scope.downloads.api.health();
      setState(() {
        _ok = true;
        _status = tr('Connesso. yt-dlp {version}', {'version': version});
      });
    } on ServerException catch (e) {
      setState(() {
        _ok = false;
        _status = e.message;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, action: action));
  }

  /// Sceglie la cartella della musica: prima il permesso del telefono, poi la cartella,
  /// infine sposta lì i brani e importa quelli che c'erano già.
  Future<void> _chooseFolder() async {
    if (!await requestStorageAccess()) {
      if (!mounted) return;
      _snack(
        tr('Senza il permesso di accedere ai file non posso usare le cartelle del telefono.'),
        action: SnackBarAction(label: tr('Impostazioni'), onPressed: openStorageSettings),
      );
      return;
    }
    final String? path;
    if (Platform.isIOS) {
      // Su iPhone le app vedono solo le proprie cartelle: si usa quella visibile nell'app File.
      path = '${(await getApplicationDocumentsDirectory()).path}/Musica';
    } else {
      path = await FilePicker.getDirectoryPath(dialogTitle: tr('Cartella della musica'));
    }
    if (path == null) return;
    await _moveTo(Directory(path), custom: path);
  }

  Future<void> _moveTo(Directory target, {String? custom}) async {
    final scope = AppScope.of(context);
    setState(() => _moving = true);
    try {
      final moved = await scope.library.moveTo(target);
      await scope.settings.setMusicDir(custom);
      final imported = await scope.library.importFolder();
      _snack(
        [
          tr('Cartella aggiornata'),
          if (moved > 0) plural(moved, '1 brano spostato', '{n} brani spostati'),
          if (imported > 0) plural(imported, '1 brano trovato', '{n} brani trovati'),
        ].join(' · '),
      );
    } on FileSystemException catch (e) {
      _snack(tr('Non riesco a usare questa cartella: {error}', {'error': e.osError?.message ?? e.message}));
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  Future<void> _rescan() async {
    final scope = AppScope.of(context);
    setState(() => _moving = true);
    final n = await scope.library.importFolder().catchError((_) => 0);
    if (!mounted) return;
    setState(() => _moving = false);
    _snack(n == 0 ? tr('Nessun brano nuovo nella cartella') : plural(n, '1 brano aggiunto', '{n} brani aggiunti'));
  }

  Widget _folderSection() {
    final library = AppScope.of(context).library;
    final custom = library.usesCustomFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('CARTELLA DELLA MUSICA'), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.folder, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(custom ? tr('Cartella scelta da te') : tr('Cartella dell\'app')),
                    SelectableText(
                      library.musicDir.path,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _moving ? null : _chooseFolder,
          icon: const Icon(Icons.drive_folder_upload),
          label: Text(
            _moving
                ? tr('Sposto i brani…')
                : Platform.isIOS
                ? tr('Mostra i brani nell\'app File')
                : tr('Scegli la cartella'),
          ),
        ),
        Row(
          children: [
            TextButton(onPressed: _moving ? null : _rescan, child: Text(tr('Cerca brani nuovi'))),
            const Spacer(),
            if (custom)
              TextButton(
                onPressed: _moving ? null : () => _moveTo(library.dir),
                child: Text(tr('Usa quella dell\'app')),
              ),
          ],
        ),
        Text(
          tr(
            'I brani scaricati vengono salvati qui. Scegliendo una cartella nuova ci sposto i brani che hai già, '
            'e aggiungo alla libreria i file audio che ci trovi dentro. Sul telefono ti chiedo prima il permesso '
            'di accedere ai file.',
          ),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _downloadSection() {
    final settings = AppScope.of(context).settings;
    final mode = settings.downloadMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('DOWNLOAD'), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        SegmentedButton<DownloadMode>(
          showSelectedIcon: false,
          style: _segmentStyle(),
          segments: [
            ButtonSegment(
              value: DownloadMode.device,
              label: Text(tr('Nell\'app')),
              icon: const Icon(Icons.phone_iphone),
            ),
            ButtonSegment(value: DownloadMode.server, label: Text(tr('Con il server')), icon: const Icon(Icons.dns)),
          ],
          selected: {mode},
          onSelectionChanged: (s) => settings.setDownloadMode(s.first),
        ),
        const SizedBox(height: 8),
        Text(
          mode == DownloadMode.server
              ? tr('Il server scarica con yt-dlp e manda i brani all\'app. Si aggiorna senza cambiare l\'app.')
              : YtDlp.available
              ? tr(
                  'La musica si cerca su YouTube Music e si scarica su questo telefono con yt-dlp, lo stesso '
                  'programma del server, senza bisogno del server. Se YouTube cambia qualcosa e i download '
                  'smettono di funzionare, aggiorna il motore qui sotto.',
                )
              : tr(
                  'La musica si cerca su YouTube Music e si scarica direttamente su questo dispositivo, '
                  'senza bisogno del server. Se un giorno YouTube cambia qualcosa e i download smettono '
                  'di funzionare, aggiorna l\'app o usa il server.',
                ),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        if (mode == DownloadMode.device && YtDlp.available) ...[const SizedBox(height: 12), const EngineTile()],
        if (mode == DownloadMode.server) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(labelText: tr('Indirizzo'), hintText: tr('http://IP-DEL-PC:8000')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            decoration: InputDecoration(labelText: tr('Token (facoltativo)')),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _testing ? null : _saveAndTest,
            child: Text(_testing ? tr('Verifica in corso…') : tr('Salva e prova la connessione')),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _ok ? Icons.check_circle : Icons.error_outline,
                  color: _ok ? Colors.greenAccent : AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_status!)),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            tr(
              'Il server è il programma Python nella cartella "server" del progetto: tienilo acceso su un PC '
              'o un Raspberry Pi. I brani già scaricati si ascoltano anche senza server.',
            ),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ],
    );
  }

  /// Tema e lingua.
  Widget _appearanceSection() {
    final settings = AppScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('ASPETTO'), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        SegmentedButton<ThemeChoice>(
          showSelectedIcon: false,
          style: _segmentStyle(),
          segments: [
            ButtonSegment(value: ThemeChoice.dark, label: Text(tr('Scuro')), icon: const Icon(Icons.dark_mode)),
            ButtonSegment(value: ThemeChoice.light, label: Text(tr('Chiaro')), icon: const Icon(Icons.light_mode)),
            ButtonSegment(
              value: ThemeChoice.system,
              label: Text(tr('Sistema')),
              icon: const Icon(Icons.brightness_auto),
            ),
          ],
          selected: {settings.theme},
          onSelectionChanged: (s) => settings.setTheme(s.first),
        ),
        const SizedBox(height: 12),
        SegmentedButton<LanguageChoice>(
          showSelectedIcon: false,
          style: _segmentStyle(),
          segments: [
            ButtonSegment(value: LanguageChoice.system, label: Text(tr('Sistema')), icon: const Icon(Icons.language)),
            // I nomi delle lingue restano nella loro lingua, così si ritrovano sempre.
            const ButtonSegment(value: LanguageChoice.italian, label: Text('Italiano')),
            const ButtonSegment(value: LanguageChoice.english, label: Text('English')),
          ],
          selected: {settings.language},
          onSelectionChanged: (s) => settings.setLanguage(s.first),
        ),
      ],
    );
  }

  ButtonStyle _segmentStyle() => SegmentedButton.styleFrom(
    selectedBackgroundColor: AppColors.accent,
    selectedForegroundColor: Colors.white,
    foregroundColor: AppColors.text,
    side: BorderSide(color: AppColors.divider),
  );

  @override
  Widget build(BuildContext context) {
    return LargeTitlePage(
      title: tr('Impostazioni'),
      backLabel: tr('Libreria'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              ListenableBuilder(listenable: AppScope.of(context).library, builder: (context, _) => _folderSection()),
              const SizedBox(height: 32),
              ListenableBuilder(listenable: AppScope.of(context).settings, builder: (context, _) => _downloadSection()),
              const SizedBox(height: 32),
              const PlaybackSection(),
              const SizedBox(height: 32),
              ListenableBuilder(
                listenable: AppScope.of(context).settings,
                builder: (context, _) => _appearanceSection(),
              ),
              const SizedBox(height: 40),
              const Center(child: AppLogo(size: 96)),
              const SizedBox(height: 8),
              const Center(
                child: Text('Carrots MP4', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La versione di yt-dlp nell'app e il pulsante per aggiornarla (solo Android).
class EngineTile extends StatefulWidget {
  const EngineTile({super.key, this.ytDlp});

  final YtDlp? ytDlp;

  @override
  State<EngineTile> createState() => _EngineTileState();
}

class _EngineTileState extends State<EngineTile> {
  YtDlp get _ytDlp => widget.ytDlp ?? YtDlp.instance;
  String? _version;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ytDlp.version().then(
      (v) {
        if (mounted) setState(() => _version = v);
      },
      onError: (Object e) {
        if (mounted) setState(() => _message = tr('Il motore non si è avviato: {error}', {'error': e}));
      },
    );
  }

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    String message;
    try {
      final r = await _ytDlp.update();
      _version = r.version ?? _version;
      message = r.updated
          ? tr('Aggiornato a {version}', {'version': r.version ?? tr('una nuova versione')})
          : tr('È già l\'ultima versione');
    } catch (e) {
      message = tr('Aggiornamento non riuscito: {error}', {'error': e});
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.memory, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Motore download')),
                  Text(_version ?? 'yt-dlp', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _update,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.system_update_alt),
          label: Text(_busy ? tr('Aggiornamento in corso…') : tr('Aggiorna motore download')),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ],
    );
  }
}
