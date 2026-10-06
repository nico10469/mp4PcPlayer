import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'cover.dart';
import 'l10n.dart';
import 'now_playing_page.dart';
import 'theme.dart';

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
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0),
                    AppColors.background.withValues(alpha: 0.9),
                    AppColors.background,
                  ],
                  stops: const [0, 0.45, 1],
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
                      tooltip: tr('Libreria'),
                      icon: Icons.library_music,
                      color: tab == 0 ? AppColors.text : AppColors.barText,
                      selected: tab == 0,
                      onPressed: onLibrary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: MiniPlayer()),
                    const SizedBox(width: 10),
                    _RoundButton(
                      tooltip: tr('Cerca'),
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
        color: AppColors.bar,
        shape: CircleBorder(
          side: BorderSide(color: selected ? AppColors.text.withValues(alpha: 0.4) : Colors.transparent),
        ),
        elevation: 6,
        shadowColor: AppColors.isDark ? Colors.black : Colors.black38,
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
/// Con [skipButtons] ci sono anche "precedente" e "successivo" (la barra del computer).
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.skipButtons = false});

  final bool skipButtons;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.player,
      builder: (context, _) {
        final track = scope.player.current;
        IconButton control(String tooltip, IconData icon, VoidCallback onPressed, {double size = 34}) => IconButton(
          tooltip: tooltip,
          iconSize: size,
          color: AppColors.text,
          disabledColor: AppColors.textSecondary,
          icon: Icon(icon),
          onPressed: track == null ? null : onPressed,
        );
        return Material(
          color: AppColors.bar,
          shape: const StadiumBorder(),
          elevation: 6,
          shadowColor: AppColors.isDark ? Colors.black : Colors.black38,
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
                            color: AppColors.surfaceHigh,
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
                          track?.title ?? tr('Non in riproduzione'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          track?.artist ?? tr('Scegli un brano dalla libreria'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: AppColors.barText),
                        ),
                      ],
                    ),
                  ),
                  if (skipButtons) control(tr('Precedente'), Icons.fast_rewind, scope.player.previous, size: 28),
                  control(
                    scope.player.isPlaying ? tr('Pausa') : tr('Riproduci'),
                    scope.player.isPlaying ? Icons.pause : Icons.play_arrow,
                    scope.player.togglePlay,
                  ),
                  if (skipButtons) control(tr('Successivo'), Icons.fast_forward, scope.player.next, size: 28),
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
