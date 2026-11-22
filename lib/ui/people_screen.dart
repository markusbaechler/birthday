import 'package:flutter/material.dart';

import '../data/database.dart';
import '../domain/dedupe.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'person_edit_screen.dart';
import 'motion.dart';
import 'person_screen.dart';
import 'widgets.dart';

/// All people A–Z with search.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    return StreamBuilder<List<Person>>(
      stream: db.watchPeople(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Person>[];
        final q = normalizeName(_query);
        final shown = q.isEmpty
            ? all
            : all
                .where((p) => normalizeName(fullName(p)).contains(q))
                .toList();
        final today = DateTime.now();
        final upcoming = {
          for (final u in upcomingFor(shown, today)) u.person.id: u.next
        };
        return ListView(
          padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, Nl.s5),
          children: [
            Row(
              children: [
                Expanded(child: SectionLabel('Personen · ${all.length}')),
                RoundIconButton(
                  icon: Icons.add,
                  tooltip: 'Person hinzufügen',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PersonEditScreen())),
                ),
              ],
            ),
            const SizedBox(height: Nl.s4),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Suchen',
                prefixIcon: Icon(Icons.search, color: Nl.muted, size: 20),
              ),
              style: Nl.body,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: Nl.s3),
            for (final p in shown)
              PressScale(child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PersonScreen(personId: p.id))),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: Nl.s3),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Nl.divider))),
                  child: Row(
                    children: [
                      PersonRing(
                          person: p, today: upcoming[p.id]?.isToday ?? false),
                      const SizedBox(width: Nl.s4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fullName(p),
                                style: Nl.body.copyWith(color: Nl.ink)),
                            Text(
                              '${p.birthDay}. ${monthNames[p.birthMonth - 1]}'
                              '${p.birthYear != null ? ' ${p.birthYear}' : ''}',
                              style: Nl.caption,
                            ),
                          ],
                        ),
                      ),
                      if (upcoming[p.id] != null)
                        Text(inDays(upcoming[p.id]!.daysUntil),
                            style: Nl.caption),
                    ],
                  ),
                ),
              )),
          ],
        );
      },
    );
  }
}
