import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bottom_bar.dart';
import 'library_page.dart';
import 'search_page.dart';

/// Struttura principale: due sezioni (libreria e ricerca), ognuna con la sua pila di pagine,
/// e la barra in basso sempre visibile sopra di esse.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _navigators = [GlobalKey<NavigatorState>(), GlobalKey<NavigatorState>()];

  void _select(int tab) {
    if (tab == _tab) {
      // Ritoccare la sezione aperta torna alla sua prima pagina.
      _navigators[tab].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _tab = tab);
    }
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: _tab,
          children: [
            _TabNavigator(navigatorKey: _navigators[0], root: const LibraryPage()),
            _TabNavigator(navigatorKey: _navigators[1], root: const SearchPage()),
          ],
        ),
        bottomNavigationBar: BottomBar(tab: _tab, onLibrary: () => _select(0), onSearch: () => _select(1)),
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
