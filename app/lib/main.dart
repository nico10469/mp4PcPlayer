import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/direct_audio.dart';
import 'services/download_manager.dart';
import 'services/library_store.dart';
import 'services/lyrics_service.dart';
import 'services/music_catalog.dart';
import 'services/player_controller.dart';
import 'services/playlist_store.dart';
import 'services/server_api.dart';
import 'services/settings.dart';
import 'ui/app_scope.dart';
import 'ui/home_shell.dart';
import 'ui/l10n.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Su Windows e Linux just_audio usa media_kit; su Android, iOS e macOS il player di sistema.
  JustAudioMediaKit.ensureInitialized();
  // Sul telefono la musica continua a schermo spento, con i comandi nella notifica,
  // nella schermata di blocco e sulle cuffie. Va fatto prima di creare il player.
  if (Platform.isAndroid || Platform.isIOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.nico10469.mp4player.playback',
      androidNotificationChannelName: 'Riproduzione',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    );
  }

  final prefs = await SharedPreferences.getInstance();
  final settings = Settings(prefs);
  final data = await getApplicationSupportDirectory();
  final custom = settings.musicDir;
  final library = LibraryStore(Directory('${data.path}/library'), musicDir: custom == null ? null : Directory(custom));
  await library.load();
  final playlists = PlaylistStore(library);
  await playlists.load();
  final player = PlayerController(library, prefs: prefs);

  runApp(Mp4PlayerApp(settings: settings, library: library, playlists: playlists, player: player));

  // Si riparte dal brano e dal punto in cui si era rimasti (in pausa).
  unawaited(player.restore().catchError((_) {}));
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
    this.music,
    this.audio,
  });

  final Settings settings;
  final LibraryStore library;
  final PlaylistStore playlists;
  final PlayerController? player;
  final LyricsService? lyrics;

  /// YouTube Music e download dell'audio nell'app (i test li sostituiscono).
  final MusicCatalog? music;
  final AudioFetcher? audio;

  @override
  State<Mp4PlayerApp> createState() => _Mp4PlayerAppState();
}

class _Mp4PlayerAppState extends State<Mp4PlayerApp> with WidgetsBindingObserver {
  late final DownloadManager _downloads = DownloadManager(
    library: widget.library,
    playlists: widget.playlists,
    api: _api(),
    mode: widget.settings.downloadMode,
    music: widget.music,
    audio: widget.audio,
  );
  late final PlayerController _player = widget.player ?? PlayerController(widget.library);
  late final LyricsService _lyrics = widget.lyrics ?? LyricsService();

  ServerApi _api() => ServerApi(baseUrl: widget.settings.serverUrl, token: widget.settings.token);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettingsChanged);
    _applyLook();
  }

  void _onSettingsChanged() {
    _downloads
      ..api = _api()
      ..mode = widget.settings.downloadMode;
    _refreshLook();
  }

  /// Tema e lingua dalle Impostazioni (con "Sistema" seguono il dispositivo).
  /// Restituisce true se sono cambiati.
  bool _applyLook() {
    final s = widget.settings;
    final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final palette = switch (s.theme) {
      ThemeChoice.dark => Palette.dark,
      ThemeChoice.light => Palette.light,
      ThemeChoice.system => dark ? Palette.dark : Palette.light,
    };
    final language = resolveLanguage(s.language);
    final changed = palette != AppColors.palette || language != appLanguage;
    AppColors.palette = palette;
    appLanguage = language;
    return changed;
  }

  void _refreshLook() {
    if (!_applyLook() || !mounted) return;
    setState(() {});
    // Colori e testi si leggono mentre le schermate si disegnano: si ridisegnano tutte,
    // anche quelle coperte (la Libreria sotto alle Impostazioni).
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  void didChangePlatformBrightness() => _refreshLook();

  @override
  void didChangeLocales(List<Locale>? locales) => _refreshLook();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        theme: buildTheme(AppColors.palette),
        home: const HomeShell(),
      ),
    );
  }
}
