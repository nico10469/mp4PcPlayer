import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/server_api.dart';
import '../services/settings.dart';
import '../services/storage_access.dart';
import 'app_scope.dart';
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
        _status = 'Connesso. yt-dlp $version';
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
        'Senza il permesso di accedere ai file non posso usare le cartelle del telefono.',
        action: SnackBarAction(label: 'Impostazioni', onPressed: openStorageSettings),
      );
      return;
    }
    final String? path;
    if (Platform.isIOS) {
      // Su iPhone le app vedono solo le proprie cartelle: si usa quella visibile nell'app File.
      path = '${(await getApplicationDocumentsDirectory()).path}/Musica';
    } else {
      path = await FilePicker.getDirectoryPath(dialogTitle: 'Cartella della musica');
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
          'Cartella aggiornata',
          if (moved > 0) moved == 1 ? '1 brano spostato' : '$moved brani spostati',
          if (imported > 0) imported == 1 ? '1 brano trovato' : '$imported brani trovati',
        ].join(' · '),
      );
    } on FileSystemException catch (e) {
      _snack('Non riesco a usare questa cartella: ${e.osError?.message ?? e.message}');
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
    _snack(n == 0 ? 'Nessun brano nuovo nella cartella' : (n == 1 ? '1 brano aggiunto' : '$n brani aggiunti'));
  }

  Widget _folderSection() {
    final library = AppScope.of(context).library;
    final custom = library.usesCustomFolder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('CARTELLA DELLA MUSICA', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                    Text(custom ? 'Cartella scelta da te' : 'Cartella dell\'app'),
                    SelectableText(
                      library.musicDir.path,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
                ? 'Sposto i brani…'
                : Platform.isIOS
                ? 'Mostra i brani nell\'app File'
                : 'Scegli la cartella',
          ),
        ),
        Row(
          children: [
            TextButton(onPressed: _moving ? null : _rescan, child: const Text('Cerca brani nuovi')),
            const Spacer(),
            if (custom)
              TextButton(
                onPressed: _moving ? null : () => _moveTo(library.dir),
                child: const Text('Usa quella dell\'app'),
              ),
          ],
        ),
        const Text(
          'I brani scaricati vengono salvati qui. Scegliendo una cartella nuova ci sposto i brani che hai già, '
          'e aggiungo alla libreria i file audio che ci trovi dentro. Sul telefono ti chiedo prima il permesso '
          'di accedere ai file.',
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
        const Text('DOWNLOAD', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        SegmentedButton<DownloadMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.accent,
            selectedForegroundColor: Colors.white,
            foregroundColor: Colors.white,
            side: const BorderSide(color: AppColors.divider),
          ),
          segments: const [
            ButtonSegment(value: DownloadMode.device, label: Text('Nell\'app'), icon: Icon(Icons.phone_iphone)),
            ButtonSegment(value: DownloadMode.server, label: Text('Con il server'), icon: Icon(Icons.dns)),
          ],
          selected: {mode},
          onSelectionChanged: (s) => settings.setDownloadMode(s.first),
        ),
        const SizedBox(height: 8),
        Text(
          mode == DownloadMode.device
              ? 'La musica si cerca su YouTube Music e si scarica direttamente su questo dispositivo, '
                    'senza bisogno del server. Se un giorno YouTube cambia qualcosa e i download smettono '
                    'di funzionare, aggiorna l\'app o usa il server.'
              : 'Il server scarica con yt-dlp e manda i brani all\'app. Si aggiorna senza cambiare l\'app.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        if (mode == DownloadMode.server) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Indirizzo', hintText: 'http://IP-DEL-PC:8000'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Token (facoltativo)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _testing ? null : _saveAndTest,
            child: Text(_testing ? 'Verifica in corso…' : 'Salva e prova la connessione'),
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
          const Text(
            'Il server è il programma Python nella cartella "server" del progetto: tienilo acceso su un PC '
            'o un Raspberry Pi. I brani già scaricati si ascoltano anche senza server.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LargeTitlePage(
      title: 'Impostazioni',
      backLabel: 'Libreria',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              ListenableBuilder(listenable: AppScope.of(context).library, builder: (context, _) => _folderSection()),
              const SizedBox(height: 32),
              ListenableBuilder(listenable: AppScope.of(context).settings, builder: (context, _) => _downloadSection()),
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
