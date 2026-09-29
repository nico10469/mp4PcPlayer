import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import '../services/player_controller.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'theme.dart';

/// La barra in basso con il brano in riproduzione.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.player,
      builder: (context, _) {
        final track = scope.player.current;
        if (track == null) return const SizedBox.shrink();
        return Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const NowPlayingPage())),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Cover(file: scope.library.coverFile(track), url: track.thumbnail, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(scope.player.isPlaying ? Icons.pause : Icons.play_arrow, size: 30),
                    onPressed: scope.player.togglePlay,
                  ),
                  IconButton(icon: const Icon(Icons.fast_forward, size: 28), onPressed: scope.player.next),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// La schermata "In riproduzione" a tutto schermo.
class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final controller = scope.player;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, size: 32),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final track = controller.current;
          if (track == null) return const SizedBox.shrink();
          return Stack(
            fit: StackFit.expand,
            children: [
              // Sfondo: la copertina sfocata e scurita, come in Apple Music.
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: Cover(file: scope.library.coverFile(track), url: track.thumbnail, size: 400, radius: 0),
                ),
              ),
              const ColoredBox(color: Color(0x99000000)),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          const Spacer(),
                          LayoutBuilder(
                            builder: (context, c) => Cover(
                              file: scope.library.coverFile(track),
                              url: track.thumbnail,
                              size: c.maxWidth,
                              radius: 12,
                            ),
                          ),
                          const Spacer(),
                          _Title(track: track),
                          const SizedBox(height: 16),
                          _Progress(controller: controller),
                          const SizedBox(height: 8),
                          _Controls(controller: controller),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final player = controller.player;
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final total = player.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        return Column(
          children: [
            Slider(
              max: max > 0 ? max : 1,
              value: pos.inMilliseconds.clamp(0, max > 0 ? max : 1).toDouble(),
              onChanged: max > 0 ? (v) => player.seek(Duration(milliseconds: v.round())) : null,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(pos), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                Text(
                  '-${formatDuration(total - pos)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});
  final PlayerController controller;

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
              icon: Icon(Icons.shuffle, color: on ? AppColors.accent : AppColors.textSecondary),
              onPressed: () async {
                if (!on) await player.shuffle();
                await player.setShuffleModeEnabled(!on);
              },
            );
          },
        ),
        IconButton(iconSize: 44, icon: const Icon(Icons.fast_rewind), onPressed: controller.previous),
        IconButton(
          iconSize: 64,
          icon: Icon(controller.isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: controller.togglePlay,
        ),
        IconButton(iconSize: 44, icon: const Icon(Icons.fast_forward), onPressed: controller.next),
        StreamBuilder<LoopMode>(
          stream: player.loopModeStream,
          builder: (context, snap) {
            final mode = snap.data ?? LoopMode.off;
            const next = {LoopMode.off: LoopMode.all, LoopMode.all: LoopMode.one, LoopMode.one: LoopMode.off};
            return IconButton(
              icon: Icon(
                mode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                color: mode == LoopMode.off ? AppColors.textSecondary : AppColors.accent,
              ),
              onPressed: () => player.setLoopMode(next[mode]!),
            );
          },
        ),
      ],
    );
  }
}
