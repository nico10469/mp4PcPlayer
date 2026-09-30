import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'cover.dart';
import 'now_playing_page.dart';
import 'theme.dart';

const _barColor = Color(0xFF3A3A3C);
const _barHeight = 64.0;

/// La barra in basso (terza immagine del mockup): libreria a sinistra,
/// brano in riproduzione al centro, ricerca a destra.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.tab, required this.onLibrary, required this.onSearch});

  /// 0 = libreria, 1 = ricerca.
  final int tab;
  final VoidCallback onLibrary;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Sfuma il contenuto che scorre sotto la barra, lasciando passare i tocchi fuori dai pulsanti.
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xE6000000), Color(0xFF000000)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 10),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
                child: Row(
                  children: [
                    _RoundButton(
                      tooltip: 'Libreria',
                      icon: Icons.library_music,
                      color: tab == 0 ? Colors.white : const Color(0xFFD1D1D6),
                      selected: tab == 0,
                      onPressed: onLibrary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: MiniPlayer()),
                    const SizedBox(width: 10),
                    _RoundButton(
                      tooltip: 'Cerca',
                      icon: Icons.search,
                      color: AppColors.accent,
                      selected: tab == 1,
                      onPressed: onSearch,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _barColor,
        shape: CircleBorder(side: BorderSide(color: selected ? const Color(0x66FFFFFF) : Colors.transparent)),
        elevation: 6,
        shadowColor: Colors.black,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: _barHeight,
            child: Icon(icon, color: color, size: 30),
          ),
        ),
      ),
    );
  }
}

/// Il pulsante lungo centrale: copertina, titolo, artista e play/pausa. Toccandolo si apre il player.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.player,
      builder: (context, _) {
        final track = scope.player.current;
        return Material(
          color: _barColor,
          shape: const StadiumBorder(),
          elevation: 6,
          shadowColor: Colors.black,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: track == null ? null : () => openNowPlaying(context),
            child: SizedBox(
              height: _barHeight,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  track == null
                      ? Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF6E6E70),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        )
                      : Cover.track(scope.library, track, size: 44, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track?.title ?? 'Non in riproduzione',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          track?.artist ?? 'Scegli un brano dalla libreria',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: Color(0xFFD1D1D6)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: scope.player.isPlaying ? 'Pausa' : 'Riproduci',
                    iconSize: 34,
                    color: Colors.white,
                    disabledColor: const Color(0xFF8E8E93),
                    icon: Icon(scope.player.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: track == null ? null : scope.player.togglePlay,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
