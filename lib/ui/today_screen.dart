import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'art.dart';
import 'celebration.dart';
import 'format.dart';
import 'import_screen.dart';
import 'motion.dart';
import 'person_edit_screen.dart';
import 'person_screen.dart';
import 'widgets.dart';

/// «Heute»: the next birthdays as large swipeable cards (photo or colour
/// light, parallax, counting number), ambient light in the colour of the
/// current card, and a quiet list of what follows.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  static const _cardCount = 8;
  final _pages = PageController(viewportFraction: 0.86);
  var _page = 0.0;
  var _celebrationChecked = false;

  @override
  void initState() {
    super.initState();
    _pages.addListener(() => setState(() => _page = _pages.page ?? 0));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
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
    return StreamBuilder<List<Person>>(
      stream: db.watchPeople(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final people = snapshot.data!;
        if (people.isEmpty) return const _EmptyStart();
        final today = DateTime.now();
        final upcoming = upcomingFor(people, today);
        _maybeCelebrate(upcoming);
        final cards = upcoming.take(_cardCount).toList();
        final rest = upcoming.skip(_cardCount).take(12).toList();
        final current = cards[_page.round().clamp(0, cards.length - 1)];
        final ambient = Nl.personColor(current.person.colorIndex,
            today: current.next.isToday);

        return Stack(
          children: [
            // Ambient light in the colour of the current card.
            Positioned(
              top: -160,
              left: -80,
              right: -80,
              height: 520,
              child: IgnorePointer(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: ambient),
                  duration: const Duration(milliseconds: 600),
                  curve: kEase,
                  builder: (context, c, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [
                        (c ?? ambient).withValues(alpha: 0.22),
                        (c ?? ambient).withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.only(top: Nl.s6, bottom: 120),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Nl.s5),
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
                SizedBox(
                  height: 468,
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: cards.length,
                    onPageChanged: (_) => HapticFeedback.selectionClick(),
                    itemBuilder: (context, i) {
                      final delta = (i - _page).clamp(-1.0, 1.0);
                      return _BirthdayCard(
                        u: cards[i],
                        delta: delta,
                        active: i == _page.round(),
                        entranceDelay: Duration(milliseconds: i == 0 ? 0 : 200),
                      );
                    },
                  ),
                ),
                const SizedBox(height: Nl.s4),
                _Dots(count: cards.length, page: _page),
                if (rest.isNotEmpty) ...[
                  const SizedBox(height: Nl.s5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Nl.s5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FadeSlideIn(
                          delay: Duration(milliseconds: 900),
                          child: SectionLabel('Danach'),
                        ),
                        const SizedBox(height: Nl.s1),
                        for (var i = 0; i < rest.length; i++)
                          FadeSlideIn(
                            delay: Duration(
                                milliseconds: 1000 + 60 * (i < 8 ? i : 8)),
                            child: _UpcomingRow(rest[i],
                                last: i == rest.length - 1),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

/// One large card. [delta] is the distance to the centre page (-1 … 1).
class _BirthdayCard extends StatelessWidget {
  const _BirthdayCard({
    required this.u,
    required this.delta,
    required this.active,
    required this.entranceDelay,
  });

  final Upcoming u;
  final double delta;
  final bool active;
  final Duration entranceDelay;

  @override
  Widget build(BuildContext context) {
    final p = u.person;
    final n = u.next;
    final name = displayName(p);
    final color = Nl.personColor(p.colorIndex, today: n.isToday);
    final scale = 1 - 0.07 * delta.abs();
    final opacity = 1 - 0.45 * delta.abs();

    final String lead;
    final String number;
    final String caption;
    if (n.isToday) {
      lead = n.turning != null ? '$name wird heute' : '$name hat heute Geburtstag';
      number = n.turning != null ? '${n.turning}' : '♥';
      caption = fullName(p);
    } else {
      lead = n.turning != null ? '$name wird ${n.turning} in' : '$name hat Geburtstag in';
      number = '${n.daysUntil}';
      caption = '${n.daysUntil == 1 ? 'Tag' : 'Tagen'} · ${formatLong(n.date)}';
    }

    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Nl.s2),
          child: PressScale(
            child: GestureDetector(
              onTap: () => _TodayScreenState.open(context, p,
                  heroTag: 'card-ring-${p.id}'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Nl.border),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PersonBackdrop(person: p, color: color, parallax: delta),
                      // Scrim so the text always reads on the photo.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0.0, 0.35, 1.0],
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
                        child: _GlassChip(
                          text: n.isToday ? 'Heute' : formatShort(n.date),
                          highlight: n.isToday,
                        ),
                      ),
                      Positioned(
                        right: Nl.s4,
                        top: Nl.s4,
                        child: Hero(
                          tag: 'card-ring-${p.id}',
                          child: PersonRing(person: p, size: 48, today: n.isToday),
                        ),
                      ),
                      Positioned(
                        left: Nl.s5,
                        right: Nl.s5,
                        bottom: Nl.s5,
                        child: _CardText(
                          key: ValueKey('card-${p.id}-$number-$active'),
                          lead: lead,
                          number: number,
                          caption: caption,
                          color: color,
                          animate: active,
                          delay: entranceDelay,
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
    );
  }
}

/// Lead, counting number and caption of a card. Counts up when the card
/// becomes active.
class _CardText extends StatefulWidget {
  const _CardText({
    super.key,
    required this.lead,
    required this.number,
    required this.caption,
    required this.color,
    required this.animate,
    required this.delay,
  });

  final String lead;
  final String number;
  final String caption;
  final Color color;
  final bool animate;
  final Duration delay;

  @override
  State<_CardText> createState() => _CardTextState();
}

class _CardTextState extends State<_CardText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  var _started = false;
  var _ticked = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_ticked && _c.value > 0.92) {
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
    final target = int.tryParse(widget.number);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final lead = kEase.transform((t / 0.35).clamp(0.0, 1.0));
        final count = kEase.transform(((t - 0.1) / 0.85).clamp(0.0, 1.0));
        final caption = kEase.transform(((t - 0.7) / 0.3).clamp(0.0, 1.0));
        final shown = target == null ? widget.number : '${(target * count).round()}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: lead,
              child: Text(widget.lead, style: Nl.lead.copyWith(color: Nl.ink)),
            ),
            Transform.translate(
              offset: Offset(0, 12 * (1 - count)),
              child: Text(
                shown,
                maxLines: 1,
                style: Nl.countdown.copyWith(color: widget.color, fontSize: 132, height: 1.0),
              ),
            ),
            const SizedBox(height: Nl.s2),
            Opacity(
              opacity: caption,
              child: Text(widget.caption, style: Nl.bodySmall.copyWith(color: Nl.inkSoft)),
            ),
          ],
        );
      },
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.text, this.highlight = false});
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(Nl.rS),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Nl.s3, vertical: Nl.s1 + 2),
            decoration: BoxDecoration(
              color: Nl.bg.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(Nl.rS),
              border: Border.all(
                  color: highlight ? Nl.accent : Colors.white.withValues(alpha: 0.12)),
            ),
            child: Text(text,
                style: Nl.caption.copyWith(color: highlight ? Nl.accent : Nl.ink)),
          ),
        ),
      );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.page});
  final int count;
  final double page;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Builder(builder: (context) {
              final focus = (1 - (page - i).abs()).clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 4 + 16 * focus,
                height: 4,
                decoration: BoxDecoration(
                  color: Color.lerp(Nl.borderControl, Nl.accent, focus),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
        ],
      );
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow(this.u, {required this.last});
  final Upcoming u;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = u.person;
    final n = u.next;
    final sub = [
      formatShort(n.date),
      if (n.turning != null) 'wird ${n.turning}',
    ].join(' · ');
    return PressScale(
      child: InkWell(
        onTap: () => _TodayScreenState.open(context, p, heroTag: 'today-ring-${p.id}'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Nl.s3),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: Nl.divider)),
          ),
          child: Row(
            children: [
              Hero(
                tag: 'today-ring-${p.id}',
                child: PersonRing(person: p, today: n.isToday),
              ),
              const SizedBox(width: Nl.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName(p), style: Nl.body.copyWith(color: Nl.ink)),
                    Text(sub, style: Nl.caption),
                  ],
                ),
              ),
              Text('${n.daysUntil}', style: Nl.display(26, weight: 300)),
              const SizedBox(width: Nl.s1),
              Text(n.daysUntil == 1 ? 'Tag' : 'Tage', style: Nl.caption),
            ],
          ),
        ),
      ),
    );
  }
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
