import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'ambient.dart';
import 'art.dart';
import 'celebration.dart';
import 'format.dart';
import 'greeting_editor.dart';
import 'import_screen.dart';
import 'motion.dart';
import 'person_edit_screen.dart';
import 'person_screen.dart';
import 'widgets.dart';

/// «Heute»: every upcoming birthday as a card, one way to browse:
/// swipe the cards or tap a face in the strip below. Cards turn in 3D while
/// swiping, react to the device tilt and never stand still (breathing rings,
/// ripples, a light sweep over the number).
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen>
    with SingleTickerProviderStateMixin {
  static const _maxCards = 40;
  static const _stripItem = 64.0;
  final _pages = PageController(viewportFraction: 0.84);
  final _strip = ScrollController();
  late final Ambient _ambient = Ambient(this);
  var _page = 0.0;
  var _celebrationChecked = false;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() {
      setState(() => _page = _pages.page ?? 0);
      _followStrip();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambient.start(
        reduceMotion: MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  @override
  void dispose() {
    _ambient.dispose();
    _pages.dispose();
    _strip.dispose();
    super.dispose();
  }

  void _followStrip() {
    if (!_strip.hasClients) return;
    final viewport = _strip.position.viewportDimension;
    final target = (_page * _stripItem - viewport / 2 + _stripItem / 2 + Nl.s5)
        .clamp(0.0, _strip.position.maxScrollExtent);
    _strip.jumpTo(target);
  }

  void _goTo(int i) {
    HapticFeedback.selectionClick();
    final distance = math.min(8, (i - _page).abs().round());
    _pages.animateToPage(i,
        duration: Duration(milliseconds: 350 + 60 * distance), curve: kEase);
  }

  void _maybeCelebrate(List<Upcoming> upcoming) {
    if (_celebrationChecked) return;
    _celebrationChecked = true;
    final todays = upcoming.where((u) => u.next.isToday).toList();
    if (todays.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final u in todays) {
        if (!mounted) return;
        if (await Celebration.alreadyShown(u.person.id)) continue;
        await Celebration.markShown(u.person.id);
        if (!mounted) return;
        await Navigator.of(context).push(CelebrationRoute(upcoming: u));
      }
    });
  }

  static void open(BuildContext context, Person p, {String? heroTag}) {
    HapticFeedback.selectionClick();
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PersonScreen(personId: p.id, heroTag: heroTag)));
  }

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    return StreamBuilder<List<Greeting>>(
      stream: db.watchGreetings(),
      builder: (context, greetSnap) => StreamBuilder<List<Person>>(
      stream: db.watchPeople(),
      builder: (context, snapshot) {
        final greetings = {
          for (final g in greetSnap.data ?? const <Greeting>[])
            '${g.personId}-${g.year}': g
        };
        if (!snapshot.hasData) return const SizedBox.shrink();
        final people = snapshot.data!;
        if (people.isEmpty) return const _EmptyStart();
        final today = DateTime.now();
        final cards = upcomingFor(people, today).take(_maxCards).toList();
        _maybeCelebrate(cards);
        final index = _page.round().clamp(0, cards.length - 1);
        final current = cards[index];
        final ambient = Nl.personColor(current.person.colorIndex,
            today: current.next.isToday);

        return Stack(
          children: [
            // Ambient light in the colour of the current card.
            Positioned(
              top: -180,
              left: -80,
              right: -80,
              height: 560,
              child: IgnorePointer(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: ambient),
                  duration: const Duration(milliseconds: 600),
                  curve: kEase,
                  builder: (context, c, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [
                        (c ?? ambient).withValues(alpha: 0.24),
                        (c ?? ambient).withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, 0),
                  child: Row(
                    children: [
                      Expanded(child: SectionLabel(formatToday(today))),
                      RoundIconButton(
                        icon: Icons.add,
                        tooltip: 'Person hinzufügen',
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const PersonEditScreen())),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Nl.s4),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: cards.length,
                    onPageChanged: (_) => HapticFeedback.selectionClick(),
                    itemBuilder: (context, i) => _BirthdayCard(
                      u: cards[i],
                      greeting: greetings[
                          '${cards[i].person.id}-${cards[i].next.date.year}'],
                      delta: (i - _page).clamp(-1.0, 1.0),
                      active: i == index,
                      ambient: _ambient,
                    ),
                  ),
                ),
                const SizedBox(height: Nl.s4),
                SizedBox(
                  height: 76,
                  child: ListView.builder(
                    controller: _strip,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Nl.s5),
                    itemCount: cards.length,
                    itemExtent: _stripItem,
                    itemBuilder: (context, i) => _StripFace(
                      u: cards[i],
                      focus: (1 - (_page - i).abs()).clamp(0.0, 1.0),
                      onTap: () => _goTo(i),
                    ),
                  ),
                ),
                const SizedBox(height: 104), // room for the glass navigation
              ],
            ),
          ],
        );
      },
    ),
    );
  }
}

/// A face in the strip below the cards. [focus] 1 = current card.
class _StripFace extends StatelessWidget {
  const _StripFace({required this.u, required this.focus, required this.onTap});
  final Upcoming u;
  final double focus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = u.next;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 0.82 + 0.18 * focus,
            child: Opacity(
              opacity: 0.45 + 0.55 * focus,
              child: PersonRing(person: u.person, size: 44, today: n.isToday),
            ),
          ),
          const SizedBox(height: Nl.s1),
          Text(
            n.isToday ? 'heute' : '${n.date.day}.${n.date.month}.',
            style: Nl.caption.copyWith(
              fontSize: 11.5,
              color: Color.lerp(Nl.muted, Nl.ink, focus),
            ),
          ),
        ],
      ),
    );
  }
}

/// One large card. [delta] is the distance to the centre page (-1 … 1).
class _BirthdayCard extends StatelessWidget {
  const _BirthdayCard({
    required this.u,
    required this.greeting,
    required this.delta,
    required this.active,
    required this.ambient,
  });

  final Upcoming u;
  final Greeting? greeting;
  final double delta;
  final bool active;
  final Ambient ambient;

  @override
  Widget build(BuildContext context) {
    final p = u.person;
    final n = u.next;
    final color = Nl.personColor(p.colorIndex, today: n.isToday);
    final hero = heroTextFor(u);
    final shrink = 1 - 0.08 * delta.abs();

    // 3D: the card turns away around its vertical axis while swiping.
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateY(-delta * 0.55);

    return Transform(
      alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
      transform: transform,
      child: Transform.scale(
        scale: shrink,
        child: Opacity(
          opacity: 1 - 0.5 * delta.abs(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Nl.s2),
            child: PressScale(
              child: GestureDetector(
                onTap: () => _TodayScreenState.open(context, p,
                    heroTag: 'card-ring-${p.id}'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      border: Border.all(color: Nl.border),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PersonBackdrop(
                          person: p,
                          color: color,
                          parallax: delta,
                          clock: ambient.clock,
                          tilt: ambient.tilt,
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.0, 0.4, 1.0],
                              colors: [
                                Color(0x330E0C12),
                                Color(0x000E0C12),
                                Color(0xF00E0C12),
                              ],
                            ),
                          ),
                        ),
                        if (n.isToday) const SparkField(),
                        Positioned(
                          left: Nl.s4,
                          top: Nl.s4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _GlassChip(
                                text: n.isToday ? 'Heute' : formatShort(n.date),
                                highlight: n.isToday,
                              ),
                              const SizedBox(height: Nl.s2),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => GreetingEditor(person: p)));
                                },
                                child: _GlassChip(
                                  text: _greetingLabel(greeting),
                                  icon: Icons.edit_note,
                                  tint: _greetingColor(greeting),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: Nl.s4,
                          top: Nl.s4,
                          child: Hero(
                            tag: 'card-ring-${p.id}',
                            child: PersonRing(
                                person: p, size: 48, today: n.isToday),
                          ),
                        ),
                        Positioned(
                          left: Nl.s5,
                          right: Nl.s5,
                          bottom: Nl.s5,
                          // The text floats slightly against the tilt: depth.
                          child: ValueListenableBuilder<Offset>(
                            valueListenable: ambient.tilt,
                            builder: (context, tl, child) => Transform.translate(
                              offset: Offset(-tl.dx * 6, -tl.dy * 4),
                              child: child,
                            ),
                            child: _CardText(
                              key: ValueKey('card-${p.id}-${hero.big}-$active'),
                              lead: hero.lead,
                              big: hero.big,
                              caption: hero.caption,
                              color: color,
                              animate: active,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _greetingLabel(Greeting? g) {
  if (g == null || (g.draft ?? '').isEmpty) return 'Gruss schreiben';
  if (g.status == GreetingStatus.sent) return 'Gruss gesendet';
  if (g.status == GreetingStatus.scheduled && g.scheduledAt != null) {
    final t = g.scheduledAt!;
    return 'Geplant ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
  return 'Entwurf bereit';
}

Color _greetingColor(Greeting? g) {
  if (g == null || (g.draft ?? '').isEmpty) return Nl.ink;
  if (g.status == GreetingStatus.scheduled) return Nl.personGreen;
  if (g.status == GreetingStatus.sent) return Nl.muted;
  return Nl.personAmber;
}

/// Lead, big age or name, caption. When the card becomes active the age
/// counts up, lands with a haptic tick and a light sweeps across it.
class _CardText extends StatefulWidget {
  const _CardText({
    super.key,
    required this.lead,
    required this.big,
    required this.caption,
    required this.color,
    required this.animate,
  });

  final String lead;
  final String big;
  final String caption;
  final Color color;
  final bool animate;

  @override
  State<_CardText> createState() => _CardTextState();
}

class _CardTextState extends State<_CardText>
    with SingleTickerProviderStateMixin {
  // 0–0.6 count up, 0.6 tick, 0.62–1.0 light sweep.
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2300));
  var _started = false;
  var _ticked = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_ticked && _c.value > 0.58) {
        _ticked = true;
        if (widget.animate) HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || !widget.animate) {
      _c.value = 1;
      _ticked = true;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b) =>
      kEase.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final target = int.tryParse(widget.big);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final lead = _seg(t, 0, 0.2);
        final count = _seg(t, 0.05, 0.6);
        final caption = _seg(t, 0.45, 0.7);
        final sweep = ((t - 0.62) / 0.38).clamp(0.0, 1.0);
        final shown =
            target == null ? widget.big : '${(target * count).round()}';
        final bigText = Text(
          shown,
          maxLines: 1,
          style: Nl.countdown.copyWith(
            color: widget.color,
            fontSize: target == null ? 104 : 148,
            height: 1.0,
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: lead,
              child: Text(widget.lead, style: Nl.lead.copyWith(color: Nl.ink)),
            ),
            Transform.translate(
              offset: Offset(0, 14 * (1 - count)),
              child: Opacity(
                opacity: target == null ? count : 1,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: sweep <= 0 || sweep >= 1
                      ? bigText
                      : ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (rect) => LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: 0.85),
                              Colors.white.withValues(alpha: 0),
                            ],
                            stops: [
                              (sweep * 1.4 - 0.4).clamp(0.0, 1.0),
                              (sweep * 1.4 - 0.2).clamp(0.0, 1.0),
                              (sweep * 1.4).clamp(0.0, 1.0),
                            ],
                          ).createShader(rect),
                          child: bigText,
                        ),
                ),
              ),
            ),
            const SizedBox(height: Nl.s2),
            Opacity(
              opacity: caption,
              child: Text(widget.caption,
                  style: Nl.bodySmall.copyWith(color: Nl.inkSoft)),
            ),
          ],
        );
      },
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.text, this.highlight = false, this.icon, this.tint});
  final String text;
  final bool highlight;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(Nl.rS),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Nl.s3, vertical: Nl.s1 + 2),
            decoration: BoxDecoration(
              color: Nl.bg.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(Nl.rS),
              border: Border.all(
                  color: highlight
                      ? Nl.accent
                      : Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: tint ?? Nl.ink),
                  const SizedBox(width: Nl.s1 + 2),
                ],
                Text(text,
                    style: Nl.caption.copyWith(
                        color: tint ?? (highlight ? Nl.accent : Nl.ink))),
              ],
            ),
          ),
        ),
      );
}

class _EmptyStart extends StatelessWidget {
  const _EmptyStart();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(formatToday(DateTime.now())),
          const Expanded(
            child: Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(painter: RingsPainter()),
                    SparkField(),
                  ],
                ),
              ),
            ),
          ),
          const Text('Noch niemand hier.', style: Nl.title),
          const SizedBox(height: Nl.s2),
          const Text(
            'Übernimm die Geburtstage aus deinen Kontakten, mit Fotos, oder erfasse die erste Person selbst.',
            style: Nl.body,
          ),
          const SizedBox(height: Nl.s5),
          FilledButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImportScreen())),
            child: const Text('Kontakte übernehmen'),
          ),
          const SizedBox(height: Nl.s2),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PersonEditScreen())),
            child: const Text('Person hinzufügen'),
          ),
        ],
      ),
    );
  }
}
