import 'package:flutter/material.dart';

import 'l10n.dart';
import 'theme.dart';

/// Il pulsante "‹ Libreria" in rosso in alto a sinistra delle pagine.
class BackLink extends StatelessWidget {
  const BackLink({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        padding: const EdgeInsets.only(left: 6, right: 8),
        alignment: Alignment.centerLeft,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      onPressed: () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back_ios_new, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Un'azione testuale in rosso nella barra in alto (es. "Ordina", "Fine").
class TextAction extends StatelessWidget {
  const TextAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// Pagina con titolo grande, come nel mockup: link indietro in alto e titolo in grassetto sotto.
class LargeTitlePage extends StatelessWidget {
  const LargeTitlePage({
    super.key,
    required this.title,
    this.backLabel,
    this.actions = const [],
    required this.slivers,
  });

  final String title;
  final String? backLabel;
  final List<Widget> actions;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            toolbarHeight: 48,
            leadingWidth: 180,
            leading: backLabel == null
                ? null
                : Align(
                    alignment: Alignment.centerLeft,
                    child: BackLink(label: backLabel!),
                  ),
            actions: [...actions, const SizedBox(width: 4)],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(title, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            ),
          ),
          ...slivers,
          const BottomSpace(),
        ],
      ),
    );
  }
}

/// Spazio in fondo alle liste, per non finire sotto la barra in basso.
class BottomSpace extends StatelessWidget {
  const BottomSpace({super.key});

  @override
  Widget build(BuildContext context) =>
      SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24));
}

/// I pulsanti grigi "Riproduci" e "Casuale" con testo e icona rossi.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.surfaceHigh,
        foregroundColor: AppColors.accent,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// Riga "Riproduci" + "Casuale".
class PlayShuffleRow extends StatelessWidget {
  const PlayShuffleRow({super.key, required this.onPlay, required this.onShuffle});

  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PillButton(icon: Icons.play_arrow, label: tr('Riproduci'), onPressed: onPlay),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: PillButton(icon: Icons.shuffle, label: tr('Casuale'), onPressed: onShuffle),
        ),
      ],
    );
  }
}

/// Titolo di una sezione, con la riga sottile sopra come nel mockup.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, indent: 20, endIndent: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}

/// Una fila orizzontale di copertine con titolo e sottotitolo (layout "Listen Now" del mockup).
class CoverCarousel extends StatelessWidget {
  const CoverCarousel({super.key, required this.itemCount, required this.itemBuilder, this.itemSize = 150});

  final int itemCount;
  final double itemSize;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemSize + 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(width: itemSize, child: itemBuilder(context, i)),
      ),
    );
  }
}

/// Una copertina del carosello: immagine, titolo e sottotitolo grigio.
class CarouselItem extends StatelessWidget {
  const CarouselItem({super.key, required this.image, required this.title, this.subtitle, this.onTap});

  final Widget image;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          image,
          const SizedBox(height: 6),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Stato vuoto centrato con titolo, testo e un pulsante rosso.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.message, this.action, this.onAction});

  final String title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: 230,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: onAction,
                child: Text(action!, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "3 brani, 12 minuti"
String tracksSummary(int count, Duration total) {
  final minutes = (total.inSeconds / 60).round();
  final songs = plural(count, '1 brano', '{n} brani');
  if (minutes >= 60) {
    final h = minutes ~/ 60;
    return tr('{songs}, {h} {hours} e {m} minuti', {
      'songs': songs,
      'h': h,
      'hours': h == 1 ? tr('ora') : tr('ore'),
      'm': minutes % 60,
    });
  }
  return '$songs, ${plural(minutes, '1 minuto', '{n} minuti')}';
}

String formatDate(DateTime d) => appLanguage == AppLanguage.english
    ? '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Il logo di Carrots MP4 (la carota in pixel art), disegnato senza sfocare i pixel.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.none,
      semanticLabel: 'Carrots MP4',
    );
  }
}
