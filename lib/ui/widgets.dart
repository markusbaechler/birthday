import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/tokens.dart';

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

/// Thin circle with initials or photo, in the person's colour.
class PersonRing extends StatelessWidget {
  const PersonRing({super.key, required this.person, this.size = 36, this.today = false});
  final Person person;
  final double size;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final color = Nl.personColor(person.colorIndex, today: today);
    final initials = [person.firstName, person.lastName]
        .where((s) => s.isNotEmpty)
        .map((s) => s.characters.first.toUpperCase())
        .take(2)
        .join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1),
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: person.photo != null
            ? Image.memory(person.photo!, fit: BoxFit.cover, gaplessPlayback: true)
            : Center(
                child: Text(initials,
                    style: TextStyle(
                        color: color,
                        fontSize: size * 0.33,
                        fontWeight: FontWeight.w500)),
              ),
      ),
    );
  }
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
