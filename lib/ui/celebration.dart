import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../domain/dedupe.dart';
import '../theme/tokens.dart';
import 'art.dart';
import 'format.dart';
import 'motion.dart';

/// The birthday spectacle: full screen, once per person and day.
abstract final class Celebration {
  static String _key(int personId) {
    final d = DateTime.now();
    return 'celebrated-${d.year}-${d.month}-${d.day}-$personId';
  }

  static Future<bool> alreadyShown(int personId) async =>
      (await SharedPreferences.getInstance()).getBool(_key(personId)) ?? false;

  static Future<void> markShown(int personId) async =>
      (await SharedPreferences.getInstance()).setBool(_key(personId), true);
}

class CelebrationRoute extends PageRouteBuilder<void> {
  CelebrationRoute({required Upcoming upcoming})
      : super(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, __, ___) => CelebrationScreen(upcoming: upcoming),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: CurvedAnimation(parent: a, curve: kEase), child: child),
        );
}

class CelebrationScreen extends StatefulWidget {
  const CelebrationScreen({super.key, required this.upcoming});
  final Upcoming upcoming;

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  var _t = 0.0; // seconds since start
  late final List<_Particle> _particles;
  final _haptics = <double>{};
  var _reduce = false;

  @override
  void initState() {
    super.initState();
    final p = widget.upcoming.person;
    final colors = [
      Nl.accent,
      const Color(0xFFF6D9A8), // warm gold
      Colors.white,
      Nl.personColor(p.colorIndex),
    ];
    final r = math.Random(p.id);
    _particles = [
      // First burst at 0.35 s, second, smaller one at 0.9 s.
      for (var i = 0; i < 150; i++) _Particle.random(r, colors, start: 0.35, power: 1),
      for (var i = 0; i < 70; i++) _Particle.random(r, colors, start: 0.9, power: 0.6),
    ];
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      _hapticAt(t);
      setState(() => _t = t);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduce) {
      _t = 10;
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _hapticAt(double t) {
    void once(double at, VoidCallback f) {
      if (t >= at && _haptics.add(at)) f();
    }

    once(0.35, HapticFeedback.heavyImpact);
    once(0.9, HapticFeedback.mediumImpact);
    for (var i = 0; i < 6; i++) {
      once(1.0 + i * 0.13, HapticFeedback.selectionClick);
    }
    once(1.85, HapticFeedback.lightImpact);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _congratulate() async {
    final p = widget.upcoming.person;
    final phone = normalizePhone(p.phone);
    Uri? uri;
    if (p.channel == Channels.whatsapp && phone != null) {
      uri = Uri.parse('https://wa.me/${phone.substring(1)}');
    } else if (p.channel == Channels.sms && phone != null) {
      uri = Uri.parse('sms:$phone');
    } else if (p.channel == Channels.email && (p.email?.isNotEmpty ?? false)) {
      uri = Uri(scheme: 'mailto', path: p.email);
    } else if (phone != null) {
      uri = Uri.parse('tel:$phone');
    }
    if (uri == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  double _seg(double start, double dur) =>
      kEase.transform(((_t - start) / dur).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final u = widget.upcoming;
    final p = u.person;
    final name = displayName(p);
    final target = u.next.turning;
    final avatar = _seg(0.0, 0.7);
    final count = _seg(0.95, 0.9);
    final lead = _seg(0.6, 0.5);
    final actions = _seg(2.0, 0.5);
    final color = Nl.accent;

    return Scaffold(
      backgroundColor: Nl.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Glow that swells with the burst.
          IgnorePointer(
            child: CustomPaint(
              painter: _GlowPainter(intensity: _seg(0.2, 0.8), t: _t),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(painter: _BurstPainter(_particles, _t)),
          ),
          const IgnorePointer(child: SparkField()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s5, Nl.s5, Nl.s6),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Schliessen',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Nl.inkSoft),
                    ),
                  ),
                  const Spacer(),
                  Transform.scale(
                    scale: 0.6 + 0.4 * avatar,
                    child: Opacity(
                      opacity: avatar,
                      child: Transform.rotate(
                        angle: (1 - avatar) * -0.6,
                        child: PersonAvatar(
                          person: p,
                          size: 148,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Nl.s5),
                  Opacity(
                    opacity: lead,
                    child: Text(
                      target != null ? '$name wird heute' : 'Heute hat Geburtstag',
                      style: Nl.lead.copyWith(color: Nl.ink),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.85 + 0.15 * count,
                    child: Opacity(
                      opacity: count,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          target != null ? '${(target * count).round()}' : name,
                          maxLines: 1,
                          style: Nl.countdown.copyWith(
                            fontVariations: const [FontVariation('wght', 260), FontVariation('opsz', 144)],
                              color: color,
                              fontSize: target != null ? 176 : 112,
                              height: 1.0),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: lead,
                    child: Text(fullName(p),
                        style: Nl.bodySmall.copyWith(color: Nl.muted)),
                  ),
                  const Spacer(),
                  Opacity(
                    opacity: actions,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - actions)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton(
                            onPressed: actions > 0.5 ? _congratulate : null,
                            child: Text('Gratulieren per ${Channels.label(p.channel)}'),
                          ),
                          const SizedBox(height: Nl.s2),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Später'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle {
  _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.start,
    required this.spin,
    required this.streak,
    required this.life,
  });

  factory _Particle.random(math.Random r, List<Color> colors,
          {required double start, required double power}) =>
      _Particle(
        angle: r.nextDouble() * 2 * math.pi,
        speed: (180 + r.nextDouble() * 520) * power,
        size: 1.2 + r.nextDouble() * 2.8,
        color: colors[r.nextInt(colors.length)],
        start: start + r.nextDouble() * 0.08,
        spin: r.nextDouble() * 6 - 3,
        streak: r.nextBool(),
        life: 1.6 + r.nextDouble() * 1.4,
      );

  final double angle, speed, size, start, spin, life;
  final Color color;
  final bool streak;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.particles, this.t);
  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.36);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final p in particles) {
      final age = t - p.start;
      if (age < 0 || age > p.life) continue;
      // Drag slows the flight, gravity pulls gently down.
      final travel = p.speed * (1 - math.exp(-2.4 * age)) / 2.4;
      final pos = origin +
          Offset(math.cos(p.angle) * travel,
              math.sin(p.angle) * travel + 90 * age * age);
      final fade = 1 - age / p.life;
      paint.color = p.color.withValues(alpha: (fade * fade).clamp(0.0, 1.0));
      if (p.streak) {
        final dir = Offset(math.cos(p.angle + p.spin * age), math.sin(p.angle + p.spin * age));
        paint.strokeWidth = p.size * 0.8;
        canvas.drawLine(pos - dir * p.size * 2.5, pos + dir * p.size * 2.5, paint);
      } else {
        canvas.drawCircle(pos, p.size, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.intensity, required this.t});
  final double intensity;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.36);
    final breathe = 0.85 + 0.15 * math.sin(t * 2 * math.pi / 4);
    final radius = size.width * 0.9 * (0.6 + 0.4 * intensity);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [
          Nl.accent.withValues(alpha: 0.28 * intensity * breathe),
          Nl.accent.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.intensity != intensity || old.t != t;
}
