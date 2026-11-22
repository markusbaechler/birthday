import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/tokens.dart';
import 'ambient.dart';

/// Round avatar with a hairline ring in the person's colour:
/// the contact photo, or initials on a faint tint.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.person,
    required this.size,
    required this.color,
  });

  final Person person;
  final double size;
  final Color color;

  String get _initials => [person.firstName, person.lastName]
      .where((s) => s.isNotEmpty)
      .map((s) => s.characters.first.toUpperCase())
      .take(2)
      .join();

  @override
  Widget build(BuildContext context) {
    final photo = person.photo;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.2),
      ),
      child: ClipOval(
        child: photo != null
            ? Image.memory(photo,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: (size * 3).round())
            : ColoredBox(
                color: color.withValues(alpha: 0.12),
                child: Center(
                  child: Text(_initials,
                      style: Nl.display(size * 0.34, weight: 350, color: color)),
                ),
              ),
      ),
    );
  }
}

/// Large backdrop for a person: the photo, or the brand motif when there is
/// no photo. With [clock] and [tilt] it lives: rings breathe and ripple,
/// photo and rings shift against the device tilt.
class PersonBackdrop extends StatelessWidget {
  const PersonBackdrop({
    super.key,
    required this.person,
    required this.color,
    this.parallax = 0,
    this.clock,
    this.tilt,
  });

  final Person person;
  final Color color;

  /// -1 … 1: horizontal shift for a parallax effect while swiping.
  final double parallax;
  final ValueListenable<double>? clock;
  final ValueListenable<Offset>? tilt;

  static final _still = ValueNotifier<double>(0);
  static final _flat = ValueNotifier<Offset>(Offset.zero);

  @override
  Widget build(BuildContext context) {
    final Uint8List? photo = person.photo;
    final tiltL = tilt ?? _flat;
    if (photo != null) {
      return ClipRect(
        child: ValueListenableBuilder<Offset>(
          valueListenable: tiltL,
          builder: (context, tl, child) => Transform.translate(
            offset: Offset(parallax * 40 + tl.dx * 18, tl.dy * 14),
            child: child,
          ),
          child: Transform.scale(
            scale: 1.18,
            child: Image.memory(photo,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: 1080,
                width: double.infinity,
                height: double.infinity),
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _GlowPainter(color)),
        CustomPaint(
          painter: LivingRingsPainter(
            color: color,
            clock: clock ?? _still,
            tilt: tiltL,
            parallax: parallax,
          ),
        ),
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Nl.surface);
    final glowCenter = Offset(size.width * 0.25, size.height * 0.78);
    final glowRadius = size.width * 0.9;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.color != color;
}
