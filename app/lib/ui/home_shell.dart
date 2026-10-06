import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bottom_bar.dart';
import 'l10n.dart';
import 'library_page.dart';
import 'search_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Da questa larghezza in su (computer, tablet in orizzontale) le sezioni stanno in una
/// barra laterale invece che nei pulsanti in basso.
const wideLayoutWidth = 900.0;

/// Struttura principale: due sezioni (libreria e ricerca), ognuna con la sua pila di pagine.
/// Sul telefono la barra in basso è sempre visibile sopra di esse; sul computer c'è una
/// barra laterale con tutte le voci della Libreria e il player in basso a tutta larghezza.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _navigators = [GlobalKey<NavigatorState>(), GlobalKey<NavigatorState>()];

  /// La voce della barra laterale evidenziata: null = la Libreria, altrimenti una delle sue voci.
  int? _section;

  void _select(int tab) {
    if (tab == _tab) {
      // Ritoccare la sezione aperta torna alla sua prima pagina.
      _navigators[tab].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = tab);
    }
    setState(() => _section = null);
  }

  /// Dalla barra laterale: apre una voce della Libreria al posto della pagina aperta.
  void _openSection(int i) {
    final nav = _navigators[0].currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute<void>(builder: (_) => librarySections()[i].page));
    setState(() {
      _tab = 0;
      _section = i;
    });
  }

  void _back() {
    final nav = _navigators[_tab].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else if (_tab != 0) {
      setState(() => _tab = 0);
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = IndexedStack(
      index: _tab,
      children: [
        _TabNavigator(navigatorKey: _navigators[0], root: const LibraryPage()),
        _TabNavigator(navigatorKey: _navigators[1], root: const SearchPage()),
      ],
    );
    final wide = MediaQuery.sizeOf(context).width >= wideLayoutWidth;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: wide
          ? Scaffold(
              body: Row(
                children: [
                  _Sidebar(
                    tab: _tab,
                    section: _section,
                    onLibrary: () => _select(0),
                    onSearch: () => _select(1),
                    onSection: _openSection,
                  ),
                  VerticalDivider(width: 1, color: AppColors.divider),
                  Expanded(child: pages),
                ],
              ),
              bottomNavigationBar: const _DesktopPlayerBar(),
            )
          : Scaffold(
              extendBody: true,
              body: pages,
              bottomNavigationBar: BottomBar(tab: _tab, onLibrary: () => _select(0), onSearch: () => _select(1)),
            ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.tab,
    required this.section,
    required this.onLibrary,
    required this.onSearch,
    required this.onSection,
  });

  final int tab;
  final int? section;
  final VoidCallback onLibrary;
  final VoidCallback onSearch;
  final ValueChanged<int> onSection;

  @override
  Widget build(BuildContext context) {
    final sections = librarySections();
    return Container(
      width: 240,
      color: AppColors.surface,
      child: SafeArea(
        right: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 0, 8, 20),
              child: Row(
                children: [
                  AppLogo(size: 36),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Carrots MP4',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            _SidebarItem(
              icon: Icons.search,
              label: tr('Cerca'),
              selected: tab == 1,
              onTap: onSearch,
            ),
            _SidebarItem(
              icon: Icons.library_music,
              label: tr('Libreria'),
              selected: tab == 0 && section == null,
              onTap: onLibrary,
            ),
            const SizedBox(height: 8),
            for (final (i, s) in sections.indexed)
              _SidebarItem(icon: s.icon, label: s.label, selected: tab == 0 && section == i, onTap: () => onSection(i)),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AppColors.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: AppColors.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Il player in basso sul computer: lo stesso mini player del telefono, con avanti e indietro.
class _DesktopPlayerBar extends StatelessWidget {
  const _DesktopPlayerBar();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: const MiniPlayer(skipButtons: true),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.navigatorKey, required this.root});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: (_) => root),
    );
  }
}
