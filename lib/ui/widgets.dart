import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/tokens.dart';
import 'art.dart';

/// Versalien-Label, e.g. «DEMNÄCHST».
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: Nl.label);
}

/// The two thin circles behind the big number (decoration only).
class RingsPainter extends CustomPainter {
  const RingsPainter({this.progress = 1});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    void ring(double radius, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          -1.5708, 6.2832 * progress, false, paint);
    }

    ring(r * 118 / 125, Nl.ringOuter);
    ring(r * 88 / 125, Nl.ringInner);
  }

  @override
  bool shouldRepaint(RingsPainter old) => old.progress != progress;
}

/// Round person avatar with a hairline ring in the person's colour.
class PersonRing extends StatelessWidget {
  const PersonRing({super.key, required this.person, this.size = 40, this.today = false});
  final Person person;
  final double size;
  final bool today;

  @override
  Widget build(BuildContext context) => PersonAvatar(
        person: person,
        size: size,
        color: today ? Colors.white : Colors.transparent,
      );
}

/// Hero: a lead line, the big thin number and a caption, rings behind.
class CountdownHero extends StatelessWidget {
  const CountdownHero({
    super.key,
    required this.lead,
    required this.number,
    required this.caption,
    required this.color,
    this.numberSize,
  });
  final String lead;
  final String number;
  final String caption;
  final Color color;

  /// Smaller size for words instead of numbers (e.g. «Heute»).
  final double? numberSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 232,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            right: -32,
            top: 0,
            child: SizedBox(
                width: 232, height: 232,
                child: CustomPaint(painter: RingsPainter())),
          ),
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(lead, style: Nl.lead),
                Semantics(
                  label: number,
                  child: Text(
                    number,
                    maxLines: 1,
                    style: Nl.countdown.copyWith(
                      color: color,
                      fontSize: numberSize,
                      height: numberSize == null ? null : 1.0,
                      letterSpacing: numberSize == null ? null : -3,
                    ),
                  ),
                ),
                const SizedBox(height: Nl.s4),
                Text(caption, style: Nl.bodySmall.copyWith(color: Nl.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card on surface with hairline border.
class NlCard extends StatelessWidget {
  const NlCard({super.key, required this.child, this.padding = Nl.s4});
  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: Nl.surface,
          borderRadius: BorderRadius.circular(Nl.rL),
          border: Border.all(color: Nl.border),
        ),
        child: child,
      );
}

/// Round 44 px icon button with hairline border.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton(
      {super.key, required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: Nl.ink),
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: const CircleBorder(side: BorderSide(color: Nl.borderIcon)),
        ),
      );
}

/// Small status pill for a greeting: planned (green, with time), draft
/// (amber), sent (muted). Nothing when there is no greeting yet.
class GreetingBadge extends StatelessWidget {
  const GreetingBadge({super.key, required this.greeting, this.compact = false});
  final Greeting? greeting;

  /// Icon only.
  final bool compact;

  static bool hasContent(Greeting? g) =>
      g != null && ((g.draft ?? '').trim().isNotEmpty || g.imagePath != null);

  @override
  Widget build(BuildContext context) {
    final g = greeting;
    if (g == null) return const SizedBox.shrink();
    final (IconData icon, String label, Color color)? look = switch (g.status) {
      GreetingStatus.scheduled => (
          Icons.schedule,
          g.scheduledAt == null
              ? 'Geplant'
              : '${g.scheduledAt!.hour.toString().padLeft(2, '0')}:${g.scheduledAt!.minute.toString().padLeft(2, '0')}',
          Nl.personGreen
        ),
      GreetingStatus.sent => (Icons.check, 'Gesendet', Nl.muted),
      _ when hasContent(g) => (Icons.edit_note, 'Entwurf', Nl.personAmber),
      _ => null,
    };
    if (look == null) return const SizedBox.shrink();
    final (icon, label, color) = look;
    return Tooltip(
      message: g.status == GreetingStatus.scheduled ? 'Gruss geplant' : label,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 5 : Nl.s2, vertical: compact ? 5 : 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Nl.rS),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(label, style: Nl.caption.copyWith(color: color, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
