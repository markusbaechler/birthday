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
      final saved = await db.saveGreeting(
        personId: u.person.id,
        year: g.year,
        channel: u.person.channel,
        status: const Value(GreetingStatus.scheduled),
        scheduledAt: Value(DateTime(d.year, d.month, d.day, 9, 0)),
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
          final upcoming = upcomingFor(people, DateTime.now())
              .where((u) => u.next.daysUntil <= _horizonDays)
              .toList();
          Greeting? gOf(Upcoming u) => byKey['${u.person.id}-${u.next.date.year}'];
          final open = upcoming
              .where((u) => (gOf(u)?.draft ?? '').isEmpty && u.next.daysUntil <= 30)
              .toList();
          final drafts = [
            for (final u in upcoming)
              if (gOf(u) case final g?
                  when g.status == GreetingStatus.draft && (g.draft ?? '').isNotEmpty)
                (u, g)
          ];
          final scheduled =
              upcoming.where((u) => gOf(u)?.status == GreetingStatus.scheduled).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, 120),
            children: [
              const SectionLabel('Grüsse'),
              const SizedBox(height: Nl.s4),
              Text(
                upcoming.isEmpty
                    ? 'In den nächsten $_horizonDays Tagen hat niemand Geburtstag.'
                    : '$scheduled geplant · ${drafts.length} Entwürfe · ${open.length} offen',
                style: Nl.title,
              ),
              const SizedBox(height: Nl.s2),
              const Text(
                'Die KI schreibt aus Profil, Insidern und Notizen. Zur geplanten Zeit kommt der fertige Text, ein Tipp öffnet den Chat.',
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
                if (drafts.isNotEmpty) ...[
                  const SizedBox(height: Nl.s2),
                  OutlinedButton(
                    onPressed: () => _planAll(drafts),
                    child: Text('${drafts.length} Entwürfe planen (09:00)'),
                  ),
                ],
              ],
              const SizedBox(height: Nl.s5),
              for (var i = 0; i < upcoming.length; i++)
                FadeSlideIn(
                  delay: Duration(milliseconds: 50 * (i < 10 ? i : 10)),
                  child: _PlanRow(
                    u: upcoming[i],
                    greeting: gOf(upcoming[i]),
                    last: i == upcoming.length - 1,
                  ),
                ),
            ],
          );
        },
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
    final (label, color) = switch (g?.status) {
      GreetingStatus.sent => ('Gesendet', Nl.muted),
      GreetingStatus.scheduled => (
          'Geplant ${g!.scheduledAt == null ? '' : '${g.scheduledAt!.hour.toString().padLeft(2, '0')}:${g.scheduledAt!.minute.toString().padLeft(2, '0')}'}',
          Nl.personGreen
        ),
      _ when (g?.draft ?? '').isNotEmpty || g?.imagePath != null => ('Entwurf', Nl.personAmber),
      _ => ('Offen', Nl.inkSoft),
    };
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Nl.s3, vertical: Nl.s1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Nl.rS),
                  border: Border.all(color: color.withValues(alpha: 0.6)),
                ),
                child: Text(label, style: Nl.caption.copyWith(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
