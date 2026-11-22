import 'package:flutter/material.dart';

import '../data/database.dart';
import '../domain/birthday.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'motion.dart';
import 'person_edit_screen.dart';
import 'widgets.dart';

class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.personId, this.heroTag});
  final int personId;

  /// Tag of the ring the user tapped, for a shared-element transition.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<Person?>(
          stream: db.watchPerson(personId),
          builder: (context, snapshot) {
            final p = snapshot.data;
            if (p == null) return const SizedBox.shrink();
            final n = nextBirthday(
                day: p.birthDay,
                month: p.birthMonth,
                year: p.birthYear,
                today: DateTime.now());
            final color = Nl.personColor(p.colorIndex, today: n.isToday);
            final name = displayName(p);
            return ListView(
              padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s5, Nl.s5, Nl.s6),
              children: [
                Row(
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Zurück',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    Hero(
                      tag: heroTag ?? 'person-ring-${p.id}',
                      child: PersonRing(
                          person: p, size: 56, today: n.isToday),
                    ),
                    const Spacer(),
                    RoundIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Profil bearbeiten',
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => PersonEditScreen(person: p))),
                    ),
                  ],
                ),
                const SizedBox(height: Nl.s5),
                AnimatedCountdownHero(
                  celebrate: n.isToday,
                  lead: n.isToday
                      ? '$name hat heute Geburtstag'
                      : '$name ${n.turning != null ? 'wird' : 'hat Geburtstag'} ${inDays(n.daysUntil)}',
                  number: n.turning != null
                      ? '${n.turning}'
                      : (n.isToday ? 'Heute' : '${n.daysUntil}'),
                  numberSize: n.turning == null && n.isToday ? 96 : null,
                  caption: [
                    fullName(p),
                    if (p.relation?.isNotEmpty ?? false) p.relation!,
                    formatLong(n.date),
                  ].join(' · '),
                  color: color,
                ),
                const SizedBox(height: Nl.s5),
                _ProfileLine(person: p),
                if (p.insiders.trim().isNotEmpty) ...[
                  const SizedBox(height: Nl.s5),
                  const SectionLabel('Insider und Erlebnisse'),
                  const SizedBox(height: Nl.s2),
                  Text(p.insiders.trim(), style: Nl.body),
                ],
                const SizedBox(height: Nl.s5),
                _Notes(personId: p.id),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.person});
  final Person person;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final parts = [
      if (p.tone?.isNotEmpty ?? false) 'Ton: ${p.tone}',
      if (p.language?.isNotEmpty ?? false) p.language!,
      'per ${Channels.label(p.channel)}',
      if (p.phone?.isNotEmpty ?? false) p.phone!,
    ];
    return Text(parts.join(' · '), style: Nl.bodySmall.copyWith(color: Nl.muted));
  }
}

class _Notes extends StatefulWidget {
  const _Notes({required this.personId});
  final int personId;

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await AppScope.of(context).addNote(widget.personId, text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    return StreamBuilder<List<Note>>(
      stream: db.watchNotes(widget.personId),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const <Note>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Notizen'),
            const SizedBox(height: Nl.s2),
            TextField(
              controller: _controller,
              style: Nl.body,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'z. B. «hat einen neuen Job in Winterthur»',
                suffixIcon: IconButton(
                  tooltip: 'Notiz speichern',
                  icon: const Icon(Icons.check, color: Nl.accent),
                  onPressed: _add,
                ),
              ),
              onSubmitted: (_) => _add(),
            ),
            for (final n in notes)
              Dismissible(
                key: ValueKey(n.id),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => db.deleteNote(n.id),
                background: const Align(
                  alignment: Alignment.centerRight,
                  child: Text('Löschen', style: TextStyle(color: Nl.dangerInk)),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: Nl.s3),
                  decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Nl.divider))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          '${monthNames[n.createdAt.month - 1].substring(0, 3)} ${n.createdAt.year}',
                          style: Nl.caption,
                        ),
                      ),
                      Expanded(child: Text(n.body, style: Nl.body)),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
