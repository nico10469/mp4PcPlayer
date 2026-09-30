import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/download_manager.dart';
import 'services/library_store.dart';
import 'services/lyrics_service.dart';
import 'services/player_controller.dart';
import 'services/playlist_store.dart';
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
  final custom = settings.musicDir;
  final library = LibraryStore(Directory('${data.path}/library'), musicDir: custom == null ? null : Directory(custom));
  await library.load();
  final playlists = PlaylistStore(library);
  await playlists.load();

  runApp(Mp4PlayerApp(settings: settings, library: library, playlists: playlists));

  // I brani copiati a mano nella cartella della musica entrano in libreria da soli.
  unawaited(library.importFolder().catchError((_) => 0));
}

class Mp4PlayerApp extends StatefulWidget {
  const Mp4PlayerApp({
    super.key,
    required this.settings,
    required this.library,
    required this.playlists,
    this.player,
    this.lyrics,
  });

  final Settings settings;
  final LibraryStore library;
  final PlaylistStore playlists;
  final PlayerController? player;
  final LyricsService? lyrics;

  @override
  State<Mp4PlayerApp> createState() => _Mp4PlayerAppState();
}

class _Mp4PlayerAppState extends State<Mp4PlayerApp> {
  late final DownloadManager _downloads = DownloadManager(
    library: widget.library,
    playlists: widget.playlists,
    api: _api(),
  );
  late final PlayerController _player = widget.player ?? PlayerController(widget.library);
  late final LyricsService _lyrics = widget.lyrics ?? LyricsService();

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
      playlists: widget.playlists,
      downloads: _downloads,
      player: _player,
      lyrics: _lyrics,
      child: MaterialApp(
        title: 'Carrots MP4',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
