import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'widgets.dart';

/// One curve for everything: strong ease-out, nothing bounces.
const kEase = Curves.easeOutCubic;

double _seg(double t, double start, double duration) =>
    kEase.transform(((t - start) / duration).clamp(0.0, 1.0));

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// The birthday moment: rings draw, the lead fades in, the number counts up
/// and lands with a light haptic tick, then the caption follows.
/// Timing as in the motion spec (2.0 s). With [celebrate] (birthday today)
/// slow sparks rise behind the number and a soft glow breathes.
class AnimatedCountdownHero extends StatefulWidget {
  const AnimatedCountdownHero({
    super.key,
    required this.lead,
    required this.number,
    required this.caption,
    required this.color,
    this.numberSize,
    this.celebrate = false,
  });

  final String lead;
  final String number;
  final String caption;
  final Color color;
  final double? numberSize;
  final bool celebrate;

  @override
  State<AnimatedCountdownHero> createState() => _AnimatedCountdownHeroState();
}

class _AnimatedCountdownHeroState extends State<AnimatedCountdownHero>
    with SingleTickerProviderStateMixin {
  static const _totalMs = 2000.0;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  var _started = false;
  var _ticked = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_ticked && _c.value * _totalMs >= 1800) {
        _ticked = true;
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduceMotion(context)) {
      _c.value = 1;
      _ticked = true;
    } else {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedCountdownHero old) {
    super.didUpdateWidget(old);
    if (old.number != widget.number && !_reduceMotion(context)) {
      _ticked = false;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = int.tryParse(widget.number);
    return SizedBox(
      height: 232,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * _totalMs;
          final rings = _seg(t, 0, 900);
          final lead = _seg(t, 250, 500);
          final count = _seg(t, 450, 1350);
          final numberOpacity = _seg(t, 450, 300);
          final caption = _seg(t, 1500, 450);
          final shown =
              target == null ? widget.number : '${(target * count).round()}';
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.celebrate)
                const Positioned.fill(child: SparkField()),
              Positioned(
                right: -32,
                top: 0,
                child: SizedBox(
                  width: 232,
                  height: 232,
                  child: CustomPaint(painter: RingsPainter(progress: rings)),
                ),
              ),
              Positioned.fill(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Opacity(
                      opacity: lead,
                      child: Transform.translate(
                        offset: Offset(0, 8 * (1 - lead)),
                        child: Text(widget.lead, style: Nl.lead),
                      ),
                    ),
                    Semantics(
                      label: widget.number,
                      excludeSemantics: true,
                      child: Opacity(
                        opacity: numberOpacity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            shown,
                            maxLines: 1,
                            style: Nl.countdown.copyWith(
                              color: widget.color,
                              fontSize: widget.numberSize ?? (target == null ? 104 : null),
                              height: target == null ? 1.0 : null,
                              letterSpacing: target == null ? -3 : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Nl.s4),
                    Opacity(
                      opacity: caption,
                      child: Transform.translate(
                        offset: Offset(0, 8 * (1 - caption)),
                        child: Text(widget.caption,
                            style: Nl.bodySmall.copyWith(color: Nl.muted)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Slow rosé sparks rising behind the hero, plus a breathing glow.
/// Only on a birthday. Stops entirely with «reduce motion».
class SparkField extends StatefulWidget {
  const SparkField({super.key});

  @override
  State<SparkField> createState() => _SparkFieldState();
}

class _SparkFieldState extends State<SparkField>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  var _seconds = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      setState(() => _seconds = elapsed.inMicroseconds / 1e6);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _SparkPainter(_seconds)),
        ),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.seconds);
  final double seconds;

  static final _sparks = List.generate(42, (i) {
    final r = math.Random(i * 7919 + 13);
    return (
      x: r.nextDouble(),
      speed: 14 + r.nextDouble() * 26,
      phase: r.nextDouble() * 1000,
      sway: 4 + r.nextDouble() * 10,
      size: 0.8 + r.nextDouble() * 1.8,
      alpha: 0.25 + r.nextDouble() * 0.55,
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Breathing glow behind the number.
    final breathe = 0.5 + 0.5 * math.sin(seconds * 2 * math.pi / 4);
    final glowCenter = Offset(size.width * 0.22, size.height * 0.62);
    final glow = Paint()
      ..shader = RadialGradient(colors: [
        Nl.accent.withValues(alpha: 0.10 + 0.08 * breathe),
        Nl.accent.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: glowCenter, radius: 170));
    canvas.drawCircle(glowCenter, 170, glow);

    // Sparks rise, sway and fade near the top.
    final paint = Paint();
    for (final s in _sparks) {
      final travel = (seconds * s.speed + s.phase) % (size.height + 40);
      final y = size.height + 20 - travel;
      final x = s.x * size.width + math.sin(seconds * 0.8 + s.phase) * s.sway;
      final fade = (y / size.height).clamp(0.0, 1.0);
      paint.color = Nl.accent.withValues(alpha: s.alpha * fade);
      canvas.drawCircle(Offset(x, y), s.size, paint);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.seconds != seconds;
}

/// Fades and slides a child in after [delay].
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduceMotion(context)) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: kEase);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
        child: widget.child,
      ),
    );
  }
}

/// Shrinks slightly while pressed, for a physical feel.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  var _down = false;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: kEase,
          child: widget.child,
        ),
      );
}

/// Soft page transition: fade with a slight zoom.
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final a = CurvedAnimation(parent: animation, curve: kEase);
    return FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(a),
        child: child,
      ),
    );
  }
}
