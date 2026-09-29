import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/download_manager.dart';
import 'services/library_store.dart';
import 'services/player_controller.dart';
import 'services/server_api.dart';
import 'services/settings.dart';
import 'ui/app_scope.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Su Windows e Linux just_audio usa media_kit; su Android, iOS e macOS il player di sistema.
  JustAudioMediaKit.ensureInitialized();

  final settings = Settings(await SharedPreferences.getInstance());
  final data = await getApplicationSupportDirectory();
  final library = LibraryStore(Directory('${data.path}/library'));
  await library.load();

  runApp(Mp4PlayerApp(settings: settings, library: library));
}

class Mp4PlayerApp extends StatefulWidget {
  const Mp4PlayerApp({super.key, required this.settings, required this.library, this.player});

  final Settings settings;
  final LibraryStore library;
  final PlayerController? player;

  @override
  State<Mp4PlayerApp> createState() => _Mp4PlayerAppState();
}

class _Mp4PlayerAppState extends State<Mp4PlayerApp> {
  late final DownloadManager _downloads = DownloadManager(library: widget.library, api: _api());
  late final PlayerController _player = widget.player ?? PlayerController(widget.library);

  ServerApi _api() => ServerApi(baseUrl: widget.settings.serverUrl, token: widget.settings.token);

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() => _downloads.api = _api();

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _player.dispose();
    _downloads.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: widget.settings,
      library: widget.library,
      downloads: _downloads,
      player: _player,
      child: MaterialApp(
        title: 'mp4Player',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
