import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/player_controller.dart';
import 'app_scope.dart';
import 'cover.dart';
import 'l10n.dart';
import 'theme.dart';

/// La coda: il brano in riproduzione e quelli che seguono, nell'ordine di ascolto.
/// Si tocca un brano per saltarci, si trascina per spostarlo, si scorre di lato per toglierlo.
Future<void> showQueue(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: QueueView()),
  );
}

class QueueView extends StatelessWidget {
  const QueueView({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final player = scope.player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final queue = player.queue;
        final current = player.current;
        final next = player.upNext;
        // Con "Casuale" l'ordine lo decide il player: si possono togliere brani, non spostarli.
        final canReorder = !player.shuffleEnabled;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr('In coda'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                  if (next.isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                      onPressed: player.clearUpNext,
                      child: Text(tr('Svuota')),
                    ),
                ],
              ),
            ),
            if (current != null) ...[
              _SectionLabel(text: tr('IN RIPRODUZIONE')),
              _QueueTile(track: current, playing: true),
            ],
            _SectionLabel(
              text: next.isEmpty
                  ? tr('NIENTE IN CODA')
                  : player.shuffleEnabled
                  ? tr('A SEGUIRE (CASUALE)')
                  : tr('A SEGUIRE'),
            ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: next.length,
                onReorderItem: (from, to) => player.moveInQueue(next[from], next[to]),
                itemBuilder: (context, i) {
                  final index = next[i];
                  final track = queue[index];
                  return Dismissible(
                    key: ValueKey('${track.id}#$index'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: AppColors.accent,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.remove_circle_outline, color: Colors.white),
                    ),
                    onDismissed: (_) => player.removeFromQueue(index),
                    child: _QueueTile(
                      track: track,
                      onTap: () => player.jumpTo(index),
                      trailing: canReorder
                          ? ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Icon(Icons.drag_handle, color: AppColors.textSecondary),
                              ),
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(text, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.track, this.playing = false, this.onTap, this.trailing});

  final Track track;
  final bool playing;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListTile(
      onTap: onTap,
      leading: Cover.track(scope.library, track),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w600, color: playing ? AppColors.accent : null),
      ),
      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: playing ? Icon(Icons.graphic_eq, color: AppColors.accent) : trailing,
    );
  }
}

/// La scheda del timer di spegnimento.
Future<void> showSleepTimer(BuildContext context) {
  final player = AppScope.of(context).player;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheetContext) {
      void set({Duration? after, bool endOfTrack = false}) {
        player.setSleepTimer(after: after, endOfTrack: endOfTrack);
        Navigator.pop(sheetContext);
      }

      final active = player.sleepTimer;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                active == null
                    ? tr('Timer di spegnimento')
                    : tr('Timer: {when}', {'when': sleepTimerLabel(active)}),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            for (final minutes in const [15, 30, 45, 60, 90])
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(tr('{n} minuti', {'n': minutes})),
                onTap: () => set(after: Duration(minutes: minutes)),
              ),
            ListTile(
              leading: const Icon(Icons.music_off_outlined),
              title: Text(tr('Alla fine del brano')),
              onTap: () => set(endOfTrack: true),
            ),
            if (active != null)
              ListTile(
                leading: const Icon(Icons.timer_off_outlined, color: AppColors.accent),
                title: Text(tr('Spegni il timer'), style: const TextStyle(color: AppColors.accent)),
                onTap: set,
              ),
          ],
        ),
      );
    },
  );
}

/// "fra 25 min" oppure "alla fine del brano".
String sleepTimerLabel(SleepTimer t) {
  if (t.endOfTrack) return tr('alla fine del brano');
  final left = t.at!.difference(DateTime.now());
  final minutes = (left.inSeconds / 60).ceil();
  return tr('fra {n} min', {'n': minutes < 1 ? 1 : minutes});
}
