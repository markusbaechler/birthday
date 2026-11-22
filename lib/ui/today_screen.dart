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
/// swipe the cards or tap a face in the strip below.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    return StreamBuilder<List<Greeting>>(
      stream: db.watchGreetings(),
      builder: (context, greetSnap) => StreamBuilder<List<Person>>(
        stream: db.watchPeople(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final people = snapshot.data!;
          if (people.isEmpty) return const _EmptyStart();
          final today = DateTime.now();
          return TodayView(
            today: today,
            cards: upcomingFor(people, today).take(40).toList(),
            greetings: {
              for (final g in greetSnap.data ?? const <Greeting>[])
                '${g.personId}-${g.year}': g
            },
          );
        },
      ),
    );
  }
}

/// The content of «Heute» without the database, so it can also be rendered
/// in screenshot tests. [greetings] are keyed «personId-year».
class TodayView extends StatefulWidget {
  const TodayView({
    super.key,
    required this.today,
    required this.cards,
    required this.greetings,
    this.celebrate = true,
  });

  final DateTime today;
  final List<Upcoming> cards;
  final Map<String, Greeting> greetings;
  final bool celebrate;

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView>
    with SingleTickerProviderStateMixin {
  static const _stripItem = 64.0;
  final _pages = PageController();
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
    if (_celebrationChecked || !widget.celebrate) return;
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
    final cards = widget.cards;
    _maybeCelebrate(cards);
    final index = _page.round().clamp(0, cards.length - 1);
    final current = cards[index];
    final ambient =
        Nl.personColor(current.person.colorIndex, today: current.next.isToday);

    return Stack(
      children: [
        // Ambient light in the colour of the current card.
        Positioned(
          top: -200,
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
                    (c ?? ambient).withValues(alpha: 0.16),
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
              padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s4, 0),
              child: Row(
                children: [
                  Expanded(child: SectionLabel(formatToday(widget.today))),
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
            const SizedBox(height: Nl.s3),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: cards.length,
                onPageChanged: (_) => HapticFeedback.selectionClick(),
                itemBuilder: (context, i) => _BirthdayCard(
                  u: cards[i],
                  greeting: widget.greetings[
                      '${cards[i].person.id}-${cards[i].next.date.year}'],
                  delta: (i - _page).clamp(-1.0, 1.0),
                  active: i == index,
                  ambient: _ambient,
                ),
              ),
            ),
            const SizedBox(height: Nl.s4),
            SizedBox(
              height: 72,
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
            const SizedBox(height: 100), // room for the glass navigation
          ],
        ),
      ],
    );
  }
}

/// A face in the strip below the cards. [focus] 1 = current card. Only the
/// current face carries colour; the others stay quiet.
class _StripFace extends StatelessWidget {
  const _StripFace({required this.u, required this.focus, required this.onTap});
  final Upcoming u;
  final double focus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = u.next;
    final own = Nl.personColor(u.person.colorIndex, today: n.isToday);
    final quiet = n.isToday ? Nl.accent.withValues(alpha: 0.7) : Nl.borderControl;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 0.84 + 0.16 * focus,
            child: Opacity(
              opacity: 0.6 + 0.4 * focus,
              child: PersonAvatar(
                person: u.person,
                size: 42,
                color: Color.lerp(quiet, own, focus)!,
                ink: Color.lerp(Nl.muted, own, focus),
              ),
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

/// One large card, composed like a poster: photo or monogram with a halo,
/// the first name large, one line with age and date, one action.
/// [delta] is the distance to the centre page (-1 … 1).
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

  static const _avatar = 116.0;

  @override
  Widget build(BuildContext context) {
    final p = u.person;
    final n = u.next;
    final color = Nl.personColor(p.colorIndex, today: n.isToday);
    final hero = heroTextFor(u);
    final hasPhoto = p.photo != null;
    final shrink = 1 - 0.06 * delta.abs();

    // 3D: the card turns away around its vertical axis while swiping.
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateY(-delta * 0.5);

    return Transform(
      alignment: delta > 0 ? Alignment.centerLeft : Alignment.centerRight,
      transform: transform,
      child: Transform.scale(
        scale: shrink,
        child: Opacity(
          opacity: 1 - 0.5 * delta.abs(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Nl.s4),
            child: PressScale(
              child: GestureDetector(
                onTap: () => _TodayViewState.open(context, p,
                    heroTag: 'card-ring-${p.id}'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: n.isToday
                              ? Nl.accent.withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.07)),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (hasPhoto) ...[
                          PersonBackdrop(
                            person: p,
                            color: color,
                            parallax: delta,
                            tilt: ambient.tilt,
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: [0.0, 0.42, 1.0],
                                colors: [
                                  Color(0x000E0C12),
                                  Color(0x140E0C12),
                                  Color(0xF50E0C12),
                                ],
                              ),
                            ),
                          ),
                        ] else
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF1A1620), Nl.surface],
                              ),
                            ),
                          ),
                        if (n.isToday) const SparkField(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              Nl.s5, Nl.s5, Nl.s5, Nl.s5),
                          child: Column(
                            children: [
                              Expanded(
                                child: hasPhoto
                                    ? const SizedBox.shrink()
                                    : Center(
                                        child: Hero(
                                          tag: 'card-ring-${p.id}',
                                          child: Halo(
                                            color: color,
                                            radius: _avatar / 2,
                                            clock: ambient.clock,
                                            tilt: ambient.tilt,
                                            child: PersonAvatar(
                                              person: p,
                                              size: _avatar,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              _CardText(
                                key: ValueKey('card-${p.id}-$active'),
                                label: hero.lead.toUpperCase(),
                                name: hero.big,
                                surname: surnameFor(p),
                                caption: hero.caption,
                                color: color,
                                animate: active,
                              ),
                              const SizedBox(height: Nl.s5),
                              _GreetingButton(
                                greeting: greeting,
                                today: n.isToday,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) =>
                                          GreetingEditor(person: p)));
                                },
                              ),
                            ],
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

/// The one action on a card. Its label carries the greeting status.
class _GreetingButton extends StatelessWidget {
  const _GreetingButton(
      {required this.greeting, required this.today, required this.onTap});
  final Greeting? greeting;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = greeting;
    final hasDraft = g != null && (g.draft ?? '').isNotEmpty;
    final (IconData icon, String text, Color tint) = switch (g?.status) {
      _ when !hasDraft => (
          Icons.auto_awesome_outlined,
          today ? 'Jetzt gratulieren' : 'Gruss vorbereiten',
          today ? Nl.onAccent : Nl.ink
        ),
      GreetingStatus.sent => (Icons.check, 'Gruss gesendet', Nl.muted),
      GreetingStatus.scheduled when g!.scheduledAt != null => (
          Icons.schedule,
          'Geplant für ${_hhmm(g.scheduledAt!)}',
          Nl.personGreen
        ),
      _ => (Icons.edit_note, 'Entwurf bereit', Nl.personAmber),
    };
    final filled = today && !hasDraft;
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: filled
                    ? Nl.accent
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(26),
                border: filled
                    ? null
                    : Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: tint),
                  const SizedBox(width: Nl.s2),
                  Text(text, style: Nl.button.copyWith(color: tint)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Label, the first name large, caption. When the card becomes active the
/// name rises in, lands with a haptic tick and a light sweeps across it.
class _CardText extends StatefulWidget {
  const _CardText({
    super.key,
    required this.label,
    required this.name,
    required this.surname,
    required this.caption,
    required this.color,
    required this.animate,
  });

  final String label;
  final String name;
  final String? surname;
  final String caption;
  final Color color;
  final bool animate;

  @override
  State<_CardText> createState() => _CardTextState();
}

class _CardTextState extends State<_CardText>
    with SingleTickerProviderStateMixin {
  // 0–0.45 rise in, 0.45 tick, 0.5–1.0 light sweep.
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));
  var _started = false;
  var _ticked = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_ticked && _c.value > 0.45) {
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
    final nameText = Text(
      widget.name,
      maxLines: 1,
      textAlign: TextAlign.center,
      style: Nl.display(84, weight: 300, color: Nl.ink, height: 1.08, spacing: -1.5),
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final label = _seg(t, 0, 0.25);
        final rise = _seg(t, 0.05, 0.45);
        final caption = _seg(t, 0.3, 0.6);
        final sweep = ((t - 0.5) / 0.5).clamp(0.0, 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: label,
              child: Text(widget.label,
                  style: Nl.label.copyWith(
                      color: widget.color, fontSize: 12.5, letterSpacing: 2.6)),
            ),
            const SizedBox(height: Nl.s2),
            Transform.translate(
              offset: Offset(0, 16 * (1 - rise)),
              child: Opacity(
                opacity: rise,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: sweep <= 0 || sweep >= 1
                      ? nameText
                      : ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (rect) => LinearGradient(
                            colors: [
                              widget.color.withValues(alpha: 0),
                              widget.color.withValues(alpha: 0.9),
                              widget.color.withValues(alpha: 0),
                            ],
                            stops: [
                              (sweep * 1.4 - 0.4).clamp(0.0, 1.0),
                              (sweep * 1.4 - 0.2).clamp(0.0, 1.0),
                              (sweep * 1.4).clamp(0.0, 1.0),
                            ],
                          ).createShader(rect),
                          child: nameText,
                        ),
                ),
              ),
            ),
            if (widget.surname != null)
              Transform.translate(
                offset: Offset(0, 10 * (1 - rise)),
                child: Opacity(
                  opacity: rise,
                  child: Text(widget.surname!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Nl.display(26, weight: 300, color: Nl.inkSoft, height: 1.2)),
                ),
              ),
            const SizedBox(height: Nl.s3),
            Opacity(
              opacity: caption,
              child: Text(widget.caption,
                  textAlign: TextAlign.center,
                  style: Nl.bodySmall.copyWith(color: Nl.inkSoft, fontSize: 15)),
            ),
          ],
        );
      },
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
