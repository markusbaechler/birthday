import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/tokens.dart';
import 'ambient.dart';
import 'format.dart';

/// Round avatar with a hairline ring in the person's colour:
/// the contact photo, or initials on a faint tint.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.person,
    required this.size,
    required this.color,
    this.ink,
  });

  final Person person;
  final double size;
  final Color color;

  /// Colour of the initials; defaults to [color].
  final Color? ink;

  String get _initials => initialsOf(person);

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
                      style: Nl.display(size * 0.34, weight: 350, color: ink ?? color)),
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

/// A soft light with concentric rings around [child] (usually the avatar).
/// The rings breathe, a ripple travels outward every four seconds, and the
/// whole halo shifts slightly against the device tilt.
class Halo extends StatelessWidget {
  const Halo({
    super.key,
    required this.color,
    required this.radius,
    required this.child,
    this.clock,
    this.tilt,
  });

  final Color color;

  /// Radius of the child; the first ring sits just outside it.
  final double radius;
  final Widget child;
  final ValueListenable<double>? clock;
  final ValueListenable<Offset>? tilt;

  static final _still = ValueNotifier<double>(0);
  static final _flat = ValueNotifier<Offset>(Offset.zero);

  @override
  Widget build(BuildContext context) {
    final tiltL = tilt ?? _flat;
    return CustomPaint(
      painter: _HaloPainter(
          color: color, radius: radius, clock: clock ?? _still, tilt: tiltL),
      child: ValueListenableBuilder<Offset>(
        valueListenable: tiltL,
        builder: (context, tl, child) => Transform.translate(
          offset: Offset(tl.dx * 5, tl.dy * 4),
          child: child,
        ),
        child: child,
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required this.color,
    required this.radius,
    required this.clock,
    required this.tilt,
  }) : super(repaint: Listenable.merge([clock, tilt]));

  final Color color;
  final double radius;
  final ValueListenable<double> clock;
  final ValueListenable<Offset> tilt;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final tl = tilt.value;
    final c = size.center(Offset.zero) + Offset(tl.dx * 12, tl.dy * 9);

    // Light behind the avatar.
    final glowR = radius * 3.4;
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(colors: [
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.08),
          color.withValues(alpha: 0),
        ], stops: const [0, 0.45, 1])
            .createShader(Rect.fromCircle(center: c, radius: glowR)),
    );

    // Rings: even steps, fading outward, breathing out of phase.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final breathe = math.sin(t * 2 * math.pi / 6 - i * 0.6);
      final r = radius + 24 + i * 34 + breathe * (1.5 + i * 0.6);
      ring.color = color.withValues(alpha: math.max(0.05, 0.26 - i * 0.06));
      canvas.drawCircle(c, r, ring);
    }

    // Ripple: one wave every 4 s.
    final phase = (t % 4.0) / 4.0;
    final rippleR = radius + 8 + phase * radius * 3.6;
    canvas.drawCircle(
      c,
      rippleR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: (1 - phase) * 0.45),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.color != color || old.radius != radius;
}
