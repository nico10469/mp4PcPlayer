import 'package:flutter/material.dart';

import 'download_page.dart';
import 'library_page.dart';
import 'player_views.dart';
import 'settings_page.dart';

/// Struttura principale: barra in basso sul telefono, barra laterale su PC e tablet.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _destinations = [
    (icon: Icons.library_music_outlined, selected: Icons.library_music, label: 'Libreria'),
    (icon: Icons.download_outlined, selected: Icons.download, label: 'Scarica'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Impostazioni'),
  ];

  void _select(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final pages = [LibraryPage(onGoToDownload: () => _select(1)), const DownloadPage(), const SettingsPage()];
    final body = IndexedStack(index: _tab, children: pages);
    final wide = MediaQuery.sizeOf(context).width >= 800;

    if (wide) {
      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _tab,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selected),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
            const MiniPlayer(),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: _select,
            height: 64,
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
            ],
          ),
        ],
      ),
    );
  }
}
