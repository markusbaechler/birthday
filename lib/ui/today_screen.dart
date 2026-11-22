import 'package:flutter/material.dart';

import '../data/database.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'import_screen.dart';
import 'person_edit_screen.dart';
import 'person_screen.dart';
import 'widgets.dart';

/// «Heute»: the next birthday as hero, the next 30 days as a quiet list.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    return StreamBuilder<List<Person>>(
      stream: db.watchPeople(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final today = DateTime.now();
        final people = snapshot.data!;
        if (people.isEmpty) return const _EmptyStart();
        final upcoming = upcomingFor(people, today);
        final first = upcoming.first;
        final rest = upcoming
            .skip(1)
            .where((u) => u.next.daysUntil <= 30)
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, Nl.s5),
          children: [
            Row(
              children: [
                Expanded(child: SectionLabel(formatToday(today))),
                RoundIconButton(
                  icon: Icons.add,
                  tooltip: 'Person hinzufügen',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PersonEditScreen())),
                ),
              ],
            ),
            const SizedBox(height: Nl.s5),
            InkWell(
              onTap: () => _open(context, first.person),
              child: _Hero(first),
            ),
            const SizedBox(height: Nl.s5),
            if (first.next.daysUntil > 30)
              const NlCard(
                child: Text(
                  'Ruhige Wochen. In den nächsten 30 Tagen hat niemand Geburtstag.',
                  style: Nl.body,
                ),
              ),
            if (rest.isNotEmpty) ...[
              const SectionLabel('Demnächst'),
              const SizedBox(height: Nl.s1),
              for (var i = 0; i < rest.length; i++)
                _UpcomingRow(rest[i], last: i == rest.length - 1),
            ],
          ],
        );
      },
    );
  }

  static void _open(BuildContext context, Person p) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PersonScreen(personId: p.id)));
}

class _Hero extends StatelessWidget {
  const _Hero(this.u);
  final Upcoming u;

  @override
  Widget build(BuildContext context) {
    final p = u.person;
    final n = u.next;
    final name = displayName(p);
    final today = n.isToday;
    final color = Nl.personColor(p.colorIndex, today: today);
    final String lead;
    final String number;
    final String caption;
    double? numberSize;
    if (today && n.turning != null) {
      lead = '$name wird heute';
      number = '${n.turning}';
      caption = fullName(p);
    } else if (today) {
      lead = '$name hat Geburtstag';
      number = 'Heute';
      numberSize = 96;
      caption = fullName(p);
    } else {
      lead = n.turning != null
          ? '$name wird ${n.turning} in'
          : '$name hat Geburtstag in';
      number = '${n.daysUntil}';
      caption =
          '${n.daysUntil == 1 ? 'Tag' : 'Tagen'} · ${formatLong(n.date)}';
    }
    return CountdownHero(
      lead: lead,
      number: number,
      numberSize: numberSize,
      caption: caption,
      color: color,
    );
  }
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
      if (n.turning != null) '${n.turning}',
    ].join(' · ');
    return InkWell(
      onTap: () => TodayScreen._open(context, p),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Nl.s3),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: Nl.divider)),
        ),
        child: Row(
          children: [
            PersonRing(person: p, today: n.isToday),
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
            Text('${n.daysUntil}', style: Nl.numberList),
            const SizedBox(width: Nl.s1),
            Text(n.daysUntil == 1 ? 'Tag' : 'Tage', style: Nl.caption),
          ],
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
      padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, Nl.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(formatToday(DateTime.now())),
          const Expanded(
            child: Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: CustomPaint(painter: RingsPainter()),
              ),
            ),
          ),
          const Text('Noch niemand hier.', style: Nl.title),
          const SizedBox(height: Nl.s2),
          const Text(
            'Übernimm die Geburtstage aus deinen Kontakten oder erfasse die erste Person selbst.',
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
