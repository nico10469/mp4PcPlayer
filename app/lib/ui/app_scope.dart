import 'package:flutter/widgets.dart';

import '../services/download_manager.dart';
import '../services/library_store.dart';
import '../services/player_controller.dart';
import '../services/playlist_store.dart';
import '../services/settings.dart';

/// Rende disponibili i servizi dell'app a tutte le schermate.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.settings,
    required this.library,
    required this.playlists,
    required this.downloads,
    required this.player,
    required super.child,
  });

  final Settings settings;
  final LibraryStore library;
  final PlaylistStore playlists;
  final DownloadManager downloads;
  final PlayerController player;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) =>
      settings != old.settings ||
      library != old.library ||
      playlists != old.playlists ||
      downloads != old.downloads ||
      player != old.player;
}
