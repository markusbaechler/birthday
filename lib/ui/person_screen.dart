import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../domain/birthday.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'art.dart';
import 'greeting_editor.dart';
import 'motion.dart';
import 'poster.dart';
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
      body: StreamBuilder<List<Greeting>>(
        stream: db.watchGreetings(),
        builder: (context, greetSnap) => StreamBuilder<Person?>(
          stream: db.watchPerson(personId),
          builder: (context, snapshot) {
            final p = snapshot.data;
            if (p == null) return const SizedBox.shrink();
            final n = nextBirthday(
                day: p.birthDay,
                month: p.birthMonth,
                year: p.birthYear,
                today: DateTime.now());
            final hero = heroTextFor(Upcoming(p, n));
            final surname = surnameFor(p);
            final mine = (greetSnap.data ?? const <Greeting>[])
                .where((g) => g.personId == p.id)
                .toList();
            final current =
                mine.where((g) => g.year == n.date.year).firstOrNull;
            final history = mine
                .where((g) =>
                    g.status == GreetingStatus.sent &&
                    (g.sentText ?? '').trim().isNotEmpty)
                .toList()
              ..sort((a, b) => b.year.compareTo(a.year));
            final poster = Poster.of(p);
            final top = MediaQuery.paddingOf(context).top;
            Widget pad(Widget child) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: Nl.s5),
                child: child);
            return ListView(
              padding: const EdgeInsets.only(bottom: Nl.s6),
              children: [
                // The same poster as the card, as the head of the page.
                SizedBox(
                  height: 440 + top,
                  child: Hero(
                    tag: heroTag ?? 'person-ring-${p.id}',
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(36)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (hasLargePhoto(p)) ...[
                            PersonBackdrop(person: p, color: poster.bg),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  stops: [0.0, 0.2, 0.5, 1.0],
                                  colors: [
                                    Color(0x80000000),
                                    Color(0x00000000),
                                    Color(0x33000000),
                                    Color(0xE6000000),
                                  ],
                                ),
                              ),
                            ),
                          ] else
                            Padding(
                              padding: EdgeInsets.only(top: top),
                              child: PosterBackdrop(
                                poster: poster,
                                figure: n.turning != null
                                    ? '${n.turning}'
                                    : hero.big.characters.first.toUpperCase(),
                              ),
                            ),
                          if (!hasLargePhoto(p))
                            Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: top + 1,
                                child: ColoredBox(color: poster.bg)),
                          if (n.isToday) const SparkField(),
                          if (!hasLargePhoto(p) && p.photo != null)
                            Positioned(
                              left: Nl.s5,
                              top: top + 84,
                              child: PersonAvatar(
                                  person: p, size: 88, color: Colors.white),
                            ),
                          Positioned(
                            top: top + Nl.s3,
                            left: Nl.s4,
                            right: Nl.s4,
                            child: Material(
                              type: MaterialType.transparency,
                              child: Row(
                                children: [
                                  _GlassButton(
                                    icon: Icons.arrow_back,
                                    tooltip: 'Zurück',
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                  const Spacer(),
                                  _GlassButton(
                                    icon: Icons.edit_outlined,
                                    tooltip: 'Profil bearbeiten',
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                PersonEditScreen(person: p))),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: Nl.s5,
                            right: Nl.s5,
                            bottom: Nl.s5,
                            child: Material(
                              type: MaterialType.transparency,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(hero.lead.toUpperCase(),
                                      style: Nl.label.copyWith(
                                          color: Colors.white
                                              .withValues(alpha: 0.9),
                                          fontSize: 13,
                                          letterSpacing: 2.4,
                                          fontWeight: FontWeight.w700,
                                          fontVariations: const [
                                            FontVariation('wght', 700)
                                          ])),
                                  const SizedBox(height: Nl.s1),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(hero.big,
                                        maxLines: 1,
                                        style: Nl.display(68,
                                            weight: 720,
                                            color: Colors.white,
                                            height: 1.02,
                                            spacing: -2.2)),
                                  ),
                                  if (surname != null)
                                    Text(surname,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Nl.display(25,
                                            weight: 450,
                                            color: Colors.white
                                                .withValues(alpha: 0.92),
                                            height: 1.2)),
                                  const SizedBox(height: Nl.s3),
                                  Text(
                                    [
                                      hero.caption,
                                      if (p.relation?.isNotEmpty ?? false)
                                        p.relation!,
                                    ].join(' · '),
                                    style: Nl.bodySmall.copyWith(
                                        color: Colors.white
                                            .withValues(alpha: 0.88),
                                        fontSize: 15.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Nl.s5),
                ...[
                      _GreetingCard(person: p, greeting: current, today: n.isToday),
                      const SizedBox(height: Nl.s3),
                      _ProfileLine(person: p),
                      if (p.insiders.trim().isNotEmpty) ...[
                        const SizedBox(height: Nl.s6),
                        const SectionLabel('Insider und Erlebnisse'),
                        const SizedBox(height: Nl.s2),
                        Text(p.insiders.trim(), style: Nl.body),
                      ],
                      const SizedBox(height: Nl.s6),
                      _Notes(personId: p.id),
                      if (history.isNotEmpty) ...[
                        const SizedBox(height: Nl.s6),
                        const SectionLabel('Bisherige Grüsse'),
                        const SizedBox(height: Nl.s1),
                        for (final g in history)
                          Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.symmetric(vertical: Nl.s3),
                            decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(color: Nl.divider))),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                    width: 72,
                                    child:
                                        Text('${g.year}', style: Nl.caption)),
                                Expanded(
                                    child: Text(g.sentText!.trim(),
                                        style: Nl.bodySmall
                                            .copyWith(color: Nl.inkSoft))),
                              ],
                            ),
                          ),
                      ],
                ].map(pad),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Round button of frosted glass, for use on a poster or photo.
class _GlassButton extends StatelessWidget {
  const _GlassButton(
      {required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      );
}

/// The greeting for the next birthday: its state and text, or the invitation
/// to prepare one. Opens the editor.
class _GreetingCard extends StatelessWidget {
  const _GreetingCard(
      {required this.person, required this.greeting, required this.today});
  final Person person;
  final Greeting? greeting;
  final bool today;

  @override
  Widget build(BuildContext context) {
    void open() {
      HapticFeedback.selectionClick();
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GreetingEditor(person: person)));
    }

    final g = greeting;
    if (!GreetingBadge.hasContent(g) && g?.status != GreetingStatus.sent) {
      return FilledButton.icon(
        onPressed: open,
        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
        label: Text(today ? 'Jetzt gratulieren' : 'Gruss vorbereiten'),
      );
    }
    final text = ((g!.status == GreetingStatus.sent ? g.sentText : null) ??
            g.draft ??
            '')
        .trim();
    final image = g.imagePath != null && File(g.imagePath!).existsSync()
        ? g.imagePath
        : null;
    final at = g.scheduledAt;
    final title = switch (g.status) {
      GreetingStatus.sent => 'Gruss gesendet',
      GreetingStatus.scheduled when at != null =>
        'Gruss geplant · ${formatShort(at)}',
      _ => 'Entwurf bereit, noch nicht geplant',
    };
    return PressScale(
      child: GestureDetector(
        onTap: open,
        child: NlCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(title,
                              style: Nl.body.copyWith(color: Nl.ink))),
                      GreetingBadge(greeting: g),
                    ]),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: Nl.s2),
                      Text(text,
                          maxLines: 4,
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
    return Text(parts.join(' · '), style: Nl.caption);
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
