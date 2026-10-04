import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import '../services/cover_colors.dart';
import '../services/player_controller.dart';
import 'app_scope.dart';
import 'artists_page.dart';
import 'cover.dart';
import 'favorites.dart';
import 'theme.dart';
import 'track_info_sheet.dart';

/// Apre il player a schermo intero, che sale dal basso sopra a tutto.
void openNowPlaying(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => const NowPlayingPage(),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

/// Il player (ultima immagine del mockup), con lo sfondo del colore dominante della copertina.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  Color _background = AppColors.surface;
  String? _colorFor;

  void _updateColor(AppScope scope, Track track) {
    if (_colorFor == track.id) return;
    _colorFor = track.id;
    final image = coverImage(scope.library, track);
    if (image == null) {
      _background = AppColors.surface;
      return;
    }
    coverColor(track.id, image).then((color) {
      if (mounted && _colorFor == track.id) setState(() => _background = color ?? AppColors.surface);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.player;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final track = controller.current;
        if (track == null) return const Scaffold();
        _updateColor(scope, track);
        final fg = foregroundFor(_background);
        final secondary = fg.withValues(alpha: 0.7);
        // Sfumatura leggera verso il basso, per dare profondità al colore.
        final bottom = Color.lerp(_background, Colors.black, 0.35)!;

        return GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 400) Navigator.pop(context);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_background, bottom],
              ),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                iconTheme: IconThemeData(color: fg),
                sliderTheme: SliderTheme.of(context).copyWith(
                  activeTrackColor: fg.withValues(alpha: 0.85),
                  inactiveTrackColor: fg.withValues(alpha: 0.25),
                  thumbColor: fg,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            IconButton(
                              tooltip: 'Chiudi',
                              icon: Icon(Icons.keyboard_arrow_down, size: 36, color: secondary),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            _Artwork(track: track, playing: controller.isPlaying),
                            const Spacer(),
                            _Progress(controller: controller, color: secondary),
                            const SizedBox(height: 18),
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: fg),
                            ),
                            const SizedBox(height: 4),
                            ArtistLine(track: track, color: secondary),
                            const SizedBox(height: 20),
                            _Controls(controller: controller, color: fg),
                            const SizedBox(height: 20),
                            _Volume(player: controller.player, color: secondary),
                            const SizedBox(height: 12),
                            _BottomRow(controller: controller, track: track, color: secondary, active: fg),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track, required this.playing});

  final Track track;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final size = c.maxWidth.clamp(0.0, MediaQuery.sizeOf(context).height * 0.42);
        // In pausa la copertina si rimpicciolisce un po', come in Apple Music.
        return AnimatedScale(
          scale: playing ? 1 : 0.86,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12))],
            ),
            child: Cover.track(scope.library, track, size: size, radius: 10),
          ),
        );
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller, required this.color});

  final PlayerController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final player = controller.player;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final total = player.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        final style = TextStyle(color: color, fontSize: 12);
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                padding: EdgeInsets.zero,
                max: max > 0 ? max : 1,
                value: pos.inMilliseconds.clamp(0, max > 0 ? max : 1).toDouble(),
                onChanged: max > 0 ? (v) => player.seek(Duration(milliseconds: v.round())) : null,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(pos), style: style),
                Text('-${formatDuration(total - pos)}', style: style),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.color});

  final PlayerController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Precedente',
          iconSize: 48,
          color: color,
          icon: const Icon(Icons.fast_rewind),
          onPressed: controller.previous,
        ),
        IconButton(
          tooltip: controller.isPlaying ? 'Pausa' : 'Riproduci',
          iconSize: 64,
          color: color,
          icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: controller.togglePlay,
        ),
        IconButton(
          tooltip: 'Successivo',
          iconSize: 48,
          color: color,
          icon: const Icon(Icons.fast_forward),
          onPressed: controller.next,
        ),
      ],
    );
  }
}

class _Volume extends StatelessWidget {
  const _Volume({required this.player, required this.color});

  final AudioPlayer player;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: player.volumeStream,
      builder: (context, snap) {
        return Row(
          children: [
            Icon(Icons.volume_mute, size: 18, color: color),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context)
                    .copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10)),
                child: Slider(value: (snap.data ?? player.volume).clamp(0, 1), onChanged: player.setVolume),
              ),
            ),
            Icon(Icons.volume_up, size: 18, color: color),
          ],
        );
      },
    );
  }
}

/// Casuale, ripetizione e "mi piace"; a destra i tre puntini dei metadati.
class _BottomRow extends StatelessWidget {
  const _BottomRow({required this.controller, required this.track, required this.color, required this.active});

  final PlayerController controller;
  final Track track;
  final Color color;
  final Color active;

  @override
  Widget build(BuildContext context) {
    final player = controller.player;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        StreamBuilder<bool>(
          stream: player.shuffleModeEnabledStream,
          builder: (context, snap) {
            final on = snap.data ?? false;
            return IconButton(
              tooltip: 'Casuale',
              icon: Icon(Icons.shuffle, color: on ? active : color.withValues(alpha: 0.5)),
              onPressed: () async {
                if (!on) await player.shuffle();
                await player.setShuffleModeEnabled(!on);
              },
            );
          },
        ),
        StreamBuilder<LoopMode>(
          stream: player.loopModeStream,
          builder: (context, snap) {
            final mode = snap.data ?? LoopMode.off;
            const next = {LoopMode.off: LoopMode.all, LoopMode.all: LoopMode.one, LoopMode.one: LoopMode.off};
            return IconButton(
              tooltip: 'Ripeti',
              icon: Icon(
                mode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                color: mode == LoopMode.off ? color.withValues(alpha: 0.5) : active,
              ),
              onPressed: () => player.setLoopMode(next[mode]!),
            );
          },
        ),
        FavoriteButton(track: track, color: active),
        IconButton(
          tooltip: 'Info brano',
          icon: Icon(Icons.more_horiz, color: active, size: 30),
          onPressed: () => showTrackInfo(context, track),
        ),
      ],
    );
  }
}

/// "Artista, Ospite — Album" sotto il titolo: ogni nome apre la pagina di quell'artista.
class ArtistLine extends StatefulWidget {
  const ArtistLine({super.key, required this.track, required this.color});

  final Track track;
  final Color color;

  @override
  State<ArtistLine> createState() => _ArtistLineState();
}

class _ArtistLineState extends State<ArtistLine> {
  final _taps = <TapGestureRecognizer>[];

  void _clear() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _open(String artist) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistPage(artist: artist)));

  @override
  Widget build(BuildContext context) {
    _clear();
    final names = artistsOf(widget.track);
    final album = widget.track.album?.trim() ?? '';
    final spans = <InlineSpan>[];
    for (final (i, name) in names.indexed) {
      if (i > 0) spans.add(const TextSpan(text: ', '));
      final tap = TapGestureRecognizer()..onTap = () => _open(name);
      _taps.add(tap);
      spans.add(TextSpan(text: name, recognizer: tap));
    }
    if (album.isNotEmpty) spans.add(TextSpan(text: ' — $album'));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 18, color: widget.color),
    );
  }
}
