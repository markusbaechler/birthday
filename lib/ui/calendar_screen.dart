import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'motion.dart';
import 'person_screen.dart';
import 'widgets.dart';

/// All birthdays in chronological order, from this month to the same month
/// next year (13 months, so every next birthday has its month),
/// grouped by month. A month strip at the top jumps to a month.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _Month {
  _Month(this.year, this.month);
  final int year;
  final int month;
  final items = <Upcoming>[];
  final key = GlobalKey();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<_Month> _months(List<Person> people, DateTime today) {
    final months = <_Month>[
      for (var i = 0; i < 13; i++)
        _Month(
          DateTime(today.year, today.month + i).year,
          DateTime(today.year, today.month + i).month,
        )
    ];
    for (final u in upcomingFor(people, today)) {
      months
          .firstWhere((m) =>
              m.year == u.next.date.year && m.month == u.next.date.month)
          .items
          .add(u);
    }
    return months;
  }

  void _jump(_Month m) {
    HapticFeedback.selectionClick();
    final ctx = m.key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 450), curve: kEase);
  }

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    return StreamBuilder<List<Person>>(
      stream: db.watchPeople(),
      builder: (context, snapshot) {
        final people = snapshot.data ?? const <Person>[];
        final today = DateTime.now();
        final months = _months(people, today);
        var row = 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, Nl.s3),
              child: SectionLabel('Kalender · ${people.length} Geburtstage'),
            ),
            _MonthStrip(months: months, onTap: _jump),
            const Divider(),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s4, Nl.s5, Nl.s6),
                children: [
                  for (final m in months) ...[
                    _MonthHeader(key: m.key, month: m),
                    if (m.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: Nl.s5),
                        child: Text('Keine Geburtstage', style: Nl.caption),
                      )
                    else
                      for (var i = 0; i < m.items.length; i++)
                        FadeSlideIn(
                          delay: Duration(
                              milliseconds: 60 * (row < 10 ? row++ : 10)),
                          child: _DayRow(
                            u: m.items[i],
                            last: i == m.items.length - 1,
                          ),
                        ),
                    const SizedBox(height: Nl.s3),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.months, required this.onTap});
  final List<_Month> months;
  final void Function(_Month) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Nl.s5),
        itemCount: months.length,
        separatorBuilder: (_, __) => const SizedBox(width: Nl.s2),
        itemBuilder: (context, i) {
          final m = months[i];
          final count = m.items.length;
          final current = i == 0;
          return PressScale(
            child: InkWell(
              borderRadius: BorderRadius.circular(Nl.rS),
              onTap: () => onTap(m),
              child: Container(
                width: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Nl.rS),
                  border: Border.all(
                      color: current ? Nl.accent : Nl.borderIcon, width: 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(monthNames[m.month - 1].substring(0, 3),
                        style: Nl.caption.copyWith(
                            color: current ? Nl.ink : Nl.inkSoft)),
                    const SizedBox(height: Nl.s1),
                    Text(
                      count == 0 ? '–' : '$count',
                      style: TextStyle(
                        fontSize: 18,
                        height: 1,
                        fontWeight: FontWeight.w300,
                        color: count == 0
                            ? Nl.muted
                            : (current ? Nl.accent : Nl.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({super.key, required this.month});
  final _Month month;

  @override
  Widget build(BuildContext context) {
    final n = month.items.length;
    return Padding(
      padding: const EdgeInsets.only(top: Nl.s4, bottom: Nl.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(monthNames[month.month - 1], style: Nl.title),
          const SizedBox(width: Nl.s3),
          Text(
            '${month.year}${n > 0 ? ' · $n ${n == 1 ? 'Geburtstag' : 'Geburtstage'}' : ''}',
            style: Nl.caption,
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.u, required this.last});
  final Upcoming u;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = u.person;
    final n = u.next;
    final color = Nl.personColor(p.colorIndex, today: n.isToday);
    final what = [
      if (n.turning != null) 'wird ${n.turning}' else 'Geburtstag',
      if (p.relation?.isNotEmpty ?? false) p.relation!,
    ].join(' · ');
    return PressScale(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  PersonScreen(personId: p.id, heroTag: 'cal-ring-${p.id}')));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Nl.s3),
          decoration: BoxDecoration(
            border:
                last ? null : const Border(bottom: BorderSide(color: Nl.divider)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${n.date.day}',
                        style: TextStyle(
                            fontSize: 30,
                            height: 1,
                            fontWeight: FontWeight.w200,
                            color: color)),
                    const SizedBox(height: Nl.s1),
                    Text(formatShort(n.date).split(' ').first,
                        style: Nl.caption),
                  ],
                ),
              ),
              Hero(
                tag: 'cal-ring-${p.id}',
                child: PersonRing(person: p, today: n.isToday),
              ),
              const SizedBox(width: Nl.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName(p), style: Nl.body.copyWith(color: Nl.ink)),
                    Text(what, style: Nl.caption),
                  ],
                ),
              ),
              Text(
                n.isToday ? 'heute' : inDays(n.daysUntil),
                style: Nl.caption.copyWith(
                    color: n.isToday ? Nl.accent : Nl.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
