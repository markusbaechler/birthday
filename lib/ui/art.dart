import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/tokens.dart';

/// Organic «cookie» outline: a circle with soft scallops (Material 3
/// Expressive shape). [rotation] turns the scallops.
Path cookiePath(Size size, {int lobes = 9, double depth = 0.045, double rotation = 0}) {
  final c = size.center(Offset.zero);
  final r = size.shortestSide / 2 / (1 + depth);
  final path = Path();
  const steps = 180;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps * 2 * math.pi;
    final rr = r * (1 + depth * math.cos(lobes * (t + rotation)));
    final p = c + Offset(math.cos(t) * rr, math.sin(t) * rr);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

class CookieClipper extends CustomClipper<Path> {
  const CookieClipper({this.rotation = 0});
  final double rotation;

  @override
  Path getClip(Size size) => cookiePath(size, rotation: rotation);

  @override
  bool shouldReclip(CookieClipper old) => old.rotation != rotation;
}

class _CookieOutline extends CustomPainter {
  const _CookieOutline(this.color, this.rotation);
  final Color color;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      cookiePath(size, rotation: rotation),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_CookieOutline old) =>
      old.color != color || old.rotation != rotation;
}

/// Avatar in cookie shape: the contact photo, or initials on a tint.
class CookieAvatar extends StatelessWidget {
  const CookieAvatar({
    super.key,
    required this.person,
    required this.size,
    required this.color,
    this.rotation = 0,
  });

  final Person person;
  final double size;
  final Color color;
  final double rotation;

  String get _initials => [person.firstName, person.lastName]
      .where((s) => s.isNotEmpty)
      .map((s) => s.characters.first.toUpperCase())
      .take(2)
      .join();

  @override
  Widget build(BuildContext context) {
    final photo = person.photo;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsets.all(2.5),
            child: ClipPath(
              clipper: CookieClipper(rotation: rotation),
              child: photo != null
                  ? Image.memory(photo,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: (size * 3).round())
                  : ColoredBox(
                      color: color.withValues(alpha: 0.14),
                      child: Center(
                        child: Text(_initials,
                            style: Nl.display(size * 0.36,
                                weight: 400, color: color)),
                      ),
                    ),
            ),
          ),
          CustomPaint(painter: _CookieOutline(color, rotation)),
        ],
      ),
    );
  }
}

/// Large backdrop for a person: the photo, or generative colour light
/// (soft orbs in the person colour) when there is no photo.
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
      painter: _OrbPainter(color, person.id, parallax),
      child: const SizedBox.expand(),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.color, this.seed, this.parallax);
  final Color color;
  final int seed;
  final double parallax;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Nl.surface);
    final r = math.Random(seed * 31 + 7);
    void orb(Color c, double alpha, double radiusFactor, double shift) {
      final center = Offset(
        size.width * (0.2 + r.nextDouble() * 0.6) + parallax * shift,
        size.height * (0.15 + r.nextDouble() * 0.5),
      );
      final radius = size.shortestSide * radiusFactor;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [
            c.withValues(alpha: alpha),
            c.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    orb(color, 0.55, 0.9, 60);
    orb(Nl.accent, 0.25, 0.7, -40);
    orb(color, 0.35, 0.5, 90);
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.color != color || old.seed != seed || old.parallax != parallax;
}
