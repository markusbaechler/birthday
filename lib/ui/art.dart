import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/tokens.dart';

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
/// no photo (concentric hairline rings in the person's colour, soft light
/// behind the number).
class PersonBackdrop extends StatelessWidget {
  const PersonBackdrop({
    super.key,
    required this.person,
    required this.color,
    this.parallax = 0,
  });

  final Person person;
  final Color color;

  /// -1 … 1: horizontal shift for a parallax effect while swiping.
  final double parallax;

  @override
  Widget build(BuildContext context) {
    final Uint8List? photo = person.photo;
    if (photo != null) {
      return ClipRect(
        child: Transform.translate(
          offset: Offset(parallax * 40, 0),
          child: Transform.scale(
            scale: 1.15,
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
    return CustomPaint(
      painter: _MotifPainter(color, parallax),
      child: const SizedBox.expand(),
    );
  }
}

class _MotifPainter extends CustomPainter {
  _MotifPainter(this.color, this.parallax);
  final Color color;
  final double parallax;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Nl.surface);

    // Soft light low left, where the big number sits.
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

    // Concentric hairline rings, top right, bleeding off the card.
    final c = Offset(size.width * 0.92 + parallax * 30, size.height * 0.18);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final r = size.width * (0.22 + i * 0.13);
      ring.color = color.withValues(alpha: math.max(0.05, 0.32 - i * 0.06));
      canvas.drawCircle(c, r, ring);
    }
  }

  @override
  bool shouldRepaint(_MotifPainter old) =>
      old.color != color || old.parallax != parallax;
}
