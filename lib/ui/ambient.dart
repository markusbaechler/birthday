import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Shared «life» for a screen: a running clock (seconds) and the device tilt
/// (-1 … 1 on both axes, smoothed). Both stand still with «reduce motion».
class Ambient {
  Ambient(TickerProvider vsync) {
    _ticker = vsync.createTicker((elapsed) {
      clock.value = elapsed.inMicroseconds / 1e6;
    });
  }

  final clock = ValueNotifier<double>(0);
  final tilt = ValueNotifier<Offset>(Offset.zero);
  late final Ticker _ticker;
  StreamSubscription<AccelerometerEvent>? _sensor;
  var _x = 0.0, _y = 0.0;

  Listenable get any => Listenable.merge([clock, tilt]);

  void start({required bool reduceMotion}) {
    if (reduceMotion) {
      stop();
      return;
    }
    if (!_ticker.isActive) _ticker.start();
    _sensor ??= accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 33))
        .listen((e) {
      // Upright phone: x = left/right tilt, y ≈ 9.8. Low-pass filter.
      final tx = (-e.x / 4.5).clamp(-1.0, 1.0);
      final ty = ((e.y - 7.0) / 4.5).clamp(-1.0, 1.0);
      _x += (tx - _x) * 0.12;
      _y += (ty - _y) * 0.12;
      tilt.value = Offset(_x, _y);
    }, onError: (_) {});
  }

  void stop() {
    if (_ticker.isActive) _ticker.stop();
    _sensor?.cancel();
    _sensor = null;
  }

  void dispose() {
    stop();
    _ticker.dispose();
    clock.dispose();
    tilt.dispose();
  }
}

/// Breathing concentric rings with a ripple that travels outward every
/// four seconds. Repaints from [clock] and [tilt] without rebuilding.
class LivingRingsPainter extends CustomPainter {
  LivingRingsPainter({
    required this.color,
    required this.clock,
    required this.tilt,
    this.parallax = 0,
  }) : super(repaint: Listenable.merge([clock, tilt]));

  final Color color;
  final ValueListenable<double> clock;
  final ValueListenable<Offset> tilt;
  final double parallax;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final tl = tilt.value;
    final c = Offset(
      size.width * 0.92 + parallax * 30 + tl.dx * 26,
      size.height * 0.18 + tl.dy * 18,
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final breathe = math.sin(t * 2 * math.pi / 5);
    for (var i = 0; i < 6; i++) {
      final r = size.width * (0.2 + i * 0.13) * (1 + 0.015 * breathe * (i + 1) / 3);
      ring.color = color.withValues(alpha: math.max(0.05, 0.34 - i * 0.055));
      canvas.drawCircle(c, r, ring);
    }
    // Ripple: one wave every 4 s, from the centre to beyond the card.
    final phase = (t % 4.0) / 4.0;
    final rippleR = size.width * (0.1 + phase * 1.1);
    final rippleA = (1 - phase) * 0.55;
    canvas.drawCircle(
      c,
      rippleR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: rippleA),
    );
  }

  @override
  bool shouldRepaint(LivingRingsPainter old) =>
      old.color != color || old.parallax != parallax;
}
