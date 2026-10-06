import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'app_scope.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// "RIPRODUZIONE" nelle Impostazioni: dissolvenza tra i brani ed equalizzatore.
class PlaybackSection extends StatelessWidget {
  const PlaybackSection({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final seconds = player.fade.inSeconds;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('RIPRODUZIONE'), style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.blur_linear, color: AppColors.accent),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('Dissolvenza tra i brani'))),
                Text(
                  seconds == 0 ? tr('No') : '$seconds s',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            Slider(
              value: seconds.toDouble(),
              max: 12,
              divisions: 12,
              activeColor: AppColors.accent,
              onChanged: (v) => player.setFade(Duration(seconds: v.round())),
            ),
            Text(
              tr('Alla fine di ogni brano il volume scende piano, e il brano dopo entra allo stesso modo.'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            if (player.equalizer != null) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.equalizer, color: AppColors.accent),
                title: Text(tr('Equalizzatore')),
                subtitle: Text(player.equalizerEnabled ? tr('Attivo') : tr('Spento')),
                trailing: Icon(Icons.chevron_right, color: AppColors.textSecondary),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EqualizerPage())),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// L'equalizzatore di Android: una barra per ogni banda di frequenza.
class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  Future<AndroidEqualizerParameters>? _params;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _params ??= AppScope.of(context).player.equalizer?.parameters;
  }

  Future<void> _save(AndroidEqualizerParameters p) =>
      AppScope.of(context).player.saveEqualizerGains([for (final b in p.bands) b.gain]);

  Future<void> _reset(AndroidEqualizerParameters p) async {
    for (final b in p.bands) {
      await b.setGain(0);
    }
    await _save(p);
  }

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return LargeTitlePage(
      title: tr('Equalizzatore'),
      backLabel: tr('Impostazioni'),
      slivers: [
        SliverToBoxAdapter(
          child: ListenableBuilder(
            listenable: player,
            builder: (context, _) => SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              activeThumbColor: AppColors.accent,
              title: Text(tr('Attivo')),
              value: player.equalizerEnabled,
              onChanged: player.setEqualizerEnabled,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: FutureBuilder<AndroidEqualizerParameters>(
            future: _params,
            builder: (context, snap) {
              final p = snap.data;
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    tr('L\'equalizzatore non è disponibile su questo telefono.'),
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              if (p == null) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(
                children: [
                  SizedBox(
                    height: 280,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final band in p.bands)
                          _Band(band: band, min: p.minDecibels, max: p.maxDecibels, onChangeEnd: () => _save(p)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                    onPressed: () => _reset(p),
                    child: Text(tr('Riporta tutto a zero')),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.band, required this.min, required this.max, required this.onChangeEnd});

  final AndroidEqualizerBand band;
  final double min;
  final double max;
  final VoidCallback onChangeEnd;

  /// 60 Hz, 230 Hz, 910 Hz, 3,6 kHz, 14 kHz…
  String get _label {
    final hz = band.centerFrequency;
    if (hz >= 1000) {
      final k = hz / 1000;
      final text = k >= 10 ? '${k.round()}' : k.toStringAsFixed(1);
      return '${appLanguage == AppLanguage.italian ? text.replaceAll('.', ',') : text} kHz';
    }
    return '${hz.round()} Hz';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: band.gainStream,
      builder: (context, snap) {
        final gain = (snap.data ?? band.gain).clamp(min, max);
        return Column(
          children: [
            Text(
              '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: gain,
                  min: min,
                  max: max,
                  activeColor: AppColors.accent,
                  onChanged: band.setGain,
                  onChangeEnd: (_) => onChangeEnd(),
                ),
              ),
            ),
            Text(_label, style: const TextStyle(fontSize: 12)),
          ],
        );
      },
    );
  }
}
