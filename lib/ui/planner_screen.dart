import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ai_service.dart';
import '../data/database.dart';
import '../data/greeting_service.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'greeting_editor.dart';
import 'motion.dart';
import 'widgets.dart';

/// «Grüsse»: the greeting planner. Every birthday of the next 60 days with
/// the state of its greeting; one tap writes drafts for all open ones,
/// another plans all drafts.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  static const _horizonDays = 60;
  var _working = false;
  var _progress = '';

  Future<void> _writeAll(List<Upcoming> open) async {
    final db = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    var done = 0;
    String? error;
    for (final u in open) {
      setState(() => _progress = 'Schreibe für ${displayName(u.person)} (${done + 1}/${open.length})');
      try {
        final v = await AiService(db).generate(u.person);
        await db.saveGreeting(
          personId: u.person.id,
          year: u.next.date.year,
          channel: u.person.channel,
          draft: Value(v.first.text),
          variants: Value(GreetingVariant.listToJson(v)),
        );
        done++;
      } on AiException catch (e) {
        error = e.message;
        break;
      }
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() {
      _working = false;
      _progress = '';
    });
    messenger.showSnackBar(SnackBar(
        content: Text(error ?? '$done Entwürfe geschrieben. Prüfen und planen.')));
  }

  Future<void> _planAll(List<(Upcoming, Greeting)> drafts) async {
    final db = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final svc = GreetingService.instance;
    await svc.requestPermissions();
    for (final (u, g) in drafts) {
      final d = u.next.date;
      var at = DateTime(d.year, d.month, d.day, 9, 0);
      final now = DateTime.now();
      if (at.isBefore(now)) at = now.add(const Duration(minutes: 10));
      final saved = await db.saveGreeting(
        personId: u.person.id,
        year: g.year,
        channel: u.person.channel,
        status: const Value(GreetingStatus.scheduled),
        scheduledAt: Value(at),
      );
      await svc.schedule(saved, u.person);
    }
    HapticFeedback.mediumImpact();
    messenger.showSnackBar(SnackBar(
        content: Text('${drafts.length} Grüsse geplant, jeweils um 09:00.')));
  }

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    return StreamBuilder<List<Person>>(
      stream: db.watchPeople(),
      builder: (context, peopleSnap) => StreamBuilder<List<Greeting>>(
        stream: db.watchGreetings(),
        builder: (context, greetSnap) {
          final people = peopleSnap.data ?? const <Person>[];
          final greetings = greetSnap.data ?? const <Greeting>[];
          final byKey = {for (final g in greetings) '${g.personId}-${g.year}': g};
          final byId = {for (final p in people) p.id: p};
          final upcoming = upcomingFor(people, DateTime.now())
              .where((u) => u.next.daysUntil <= _horizonDays)
              .toList();
          Greeting? gOf(Upcoming u) => byKey['${u.person.id}-${u.next.date.year}'];
          // Everything planned, however far ahead, by time.
          final planned = [
            for (final g in greetings)
              if (g.status == GreetingStatus.scheduled && byId[g.personId] != null)
                (byId[g.personId]!, g)
          ]..sort((a, b) => (a.$2.scheduledAt ?? DateTime(9999))
              .compareTo(b.$2.scheduledAt ?? DateTime(9999)));
          final draftRows = [
            for (final u in upcoming)
              if (gOf(u) case final g?
                  when g.status == GreetingStatus.draft && GreetingBadge.hasContent(g))
                (u, g)
          ];
          final openRows = upcoming
              .where((u) => !GreetingBadge.hasContent(gOf(u)))
              .toList();
          final open = openRows.where((u) => u.next.daysUntil <= 30).toList();

          var i = 0;
          Widget row(Upcoming u, Greeting? g, bool last) => FadeSlideIn(
                delay: Duration(milliseconds: 40 * (i < 10 ? i++ : 10)),
                child: _PlanRow(u: u, greeting: g, last: last),
              );

          return ListView(
            padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, 120),
            children: [
              const SectionLabel('Grüsse'),
              const SizedBox(height: Nl.s4),
              Text(
                '${planned.length} geplant · ${draftRows.length} Entwürfe · ${openRows.length} offen',
                style: Nl.title,
              ),
              const SizedBox(height: Nl.s2),
              const Text(
                'Zur geplanten Zeit kommt eine Benachrichtigung mit dem fertigen Gruss. Ein Tipp öffnet den Chat, du tippst nur noch auf Senden.',
                style: Nl.bodySmall,
              ),
              const SizedBox(height: Nl.s5),
              if (_working)
                Row(children: [
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 1.5)),
                  const SizedBox(width: Nl.s3),
                  Expanded(child: Text(_progress, style: Nl.bodySmall)),
                ])
              else ...[
                if (open.isNotEmpty)
                  FilledButton(
                    onPressed: () => _writeAll(open),
                    child: Text(open.length == 1
                        ? '1 Entwurf schreiben lassen'
                        : '${open.length} Entwürfe schreiben lassen'),
                  ),
                if (draftRows.isNotEmpty) ...[
                  const SizedBox(height: Nl.s2),
                  OutlinedButton(
                    onPressed: () => _planAll(draftRows),
                    child: Text('${draftRows.length} Entwürfe planen (09:00)'),
                  ),
                ],
              ],

              // Planned
              const SizedBox(height: Nl.s6),
              const SectionLabel('Geplant'),
              const SizedBox(height: Nl.s3),
              if (planned.isEmpty)
                const Text('Noch nichts geplant.', style: Nl.caption)
              else
                for (final (p, g) in planned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Nl.s3),
                    child: _PlannedCard(person: p, greeting: g),
                  ),

              if (draftRows.isNotEmpty) ...[
                const SizedBox(height: Nl.s5),
                const SectionLabel('Entwürfe'),
                const SizedBox(height: Nl.s1),
                for (var k = 0; k < draftRows.length; k++)
                  row(draftRows[k].$1, draftRows[k].$2, k == draftRows.length - 1),
              ],
              if (openRows.isNotEmpty) ...[
                const SizedBox(height: Nl.s5),
                const SectionLabel('Offen · nächste $_horizonDays Tage'),
                const SizedBox(height: Nl.s1),
                for (var k = 0; k < openRows.length; k++)
                  row(openRows[k], gOf(openRows[k]), k == openRows.length - 1),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A planned greeting at a glance: when, for whom, what goes out.
class _PlannedCard extends StatelessWidget {
  const _PlannedCard({required this.person, required this.greeting});
  final Person person;
  final Greeting greeting;

  @override
  Widget build(BuildContext context) {
    final g = greeting;
    final at = g.scheduledAt;
    final past = at != null && at.isBefore(DateTime.now());
    final image = g.imagePath != null && File(g.imagePath!).existsSync()
        ? g.imagePath
        : null;
    return PressScale(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GreetingEditor(person: person)));
        },
        child: Container(
          padding: const EdgeInsets.all(Nl.s4),
          decoration: BoxDecoration(
            color: Nl.surface,
            borderRadius: BorderRadius.circular(Nl.rL),
            border: Border.all(color: Nl.personGreen.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(at == null ? '–' : '${at.day}.${at.month}.',
                        style: Nl.display(24, weight: 300, color: Nl.ink, height: 1.1)),
                    const SizedBox(height: 2),
                    Text(
                      at == null
                          ? ''
                          : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                      style: Nl.caption.copyWith(
                          color: past ? Nl.dangerInk : Nl.personGreen),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName(person),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Nl.body.copyWith(color: Nl.ink)),
                    Text(
                      [
                        Channels.label(person.channel),
                        if (image != null) 'mit Karte',
                        if (past) 'Zeit verpasst',
                      ].join(' · '),
                      style: Nl.caption.copyWith(
                          color: past ? Nl.dangerInk : Nl.muted),
                    ),
                    if ((g.draft ?? '').isNotEmpty) ...[
                      const SizedBox(height: Nl.s2),
                      Text(g.draft!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Nl.bodySmall.copyWith(color: Nl.inkSoft)),
                    ],
                  ],
                ),
              ),
              if (image != null) ...[
                const SizedBox(width: Nl.s3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Nl.rS),
                  child: Image.file(File(image),
                      width: 56, height: 70, fit: BoxFit.cover, cacheWidth: 168),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.u, required this.greeting, required this.last});
  final Upcoming u;
  final Greeting? greeting;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = u.person;
    final n = u.next;
    final g = greeting;
    return PressScale(
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GreetingEditor(person: p)));
        },
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
                    Text(displayName(p), style: Nl.body.copyWith(color: Nl.ink)),
                    Text(
                      [
                        n.isToday ? 'heute' : formatShort(n.date),
                        if (n.turning != null) 'wird ${n.turning}',
                      ].join(' · '),
                      style: Nl.caption,
                    ),
                    if ((g?.draft ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Nl.s1),
                        child: Text(g!.draft!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Nl.caption.copyWith(color: Nl.inkSoft)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Nl.s3),
              if (GreetingBadge.hasContent(g) || g?.status == GreetingStatus.sent)
                GreetingBadge(greeting: g)
              else
                Text('Offen', style: Nl.caption.copyWith(color: Nl.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}
