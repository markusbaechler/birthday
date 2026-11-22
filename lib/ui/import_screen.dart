import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/import_service.dart';
import '../domain/dedupe.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'widgets.dart';

enum _Stage { asking, denied, reading, review, saving, done }

/// Import birthdays from the phone contacts, with duplicate review.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  var _stage = _Stage.asking;
  ImportPlan? _plan;
  var _found = 0;
  final _photos = <String, Uint8List?>{};
  final _mergeReviewed = <int>{};
  var _written = 0;
  late ImportService _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _service = ImportService(AppScope.of(context));
  }

  Future<void> _start() async {
    final granted = await _service.requestPermission();
    if (!granted) {
      setState(() => _stage = _Stage.denied);
      return;
    }
    setState(() => _stage = _Stage.reading);
    final entries = await _service.readContactsWithBirthday();
    for (final e in entries) {
      _photos[e.candidate.contactId!] = e.photo;
    }
    final existing = await _service.existingCandidates();
    final plan = buildImportPlan(
      incoming: [for (final e in entries) e.candidate],
      existing: existing,
    );
    setState(() {
      _found = entries.length;
      _plan = plan;
      // Default: likely pairs are treated as the same person.
      _mergeReviewed
        ..clear()
        ..addAll(List.generate(plan.toReview.length, (i) => i));
      _stage = _Stage.review;
    });
  }

  Future<void> _apply() async {
    setState(() => _stage = _Stage.saving);
    final written =
        await _service.apply(_plan!, _photos, mergeReviewed: _mergeReviewed);
    setState(() {
      _written = written;
      _stage = _Stage.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s5, Nl.s5, Nl.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                RoundIconButton(
                  icon: Icons.close,
                  tooltip: 'Schliessen',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
              const SizedBox(height: Nl.s5),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.asking:
        return _Intro(onStart: _start);
      case _Stage.denied:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kein Zugriff auf die Kontakte.', style: Nl.title),
            SizedBox(height: Nl.s2),
            Text(
              'Du kannst den Zugriff in den Android-Einstellungen unter Apps › Geburtstage › Berechtigungen erlauben oder Personen selbst erfassen.',
              style: Nl.body,
            ),
          ],
        );
      case _Stage.reading:
      case _Stage.saving:
        return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
      case _Stage.review:
        return _review();
      case _Stage.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CountdownHero(
              lead: 'Übernommen',
              number: '$_written',
              caption: 'Personen neu oder ergänzt',
              color: Nl.personGreen,
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fertig'),
            ),
          ],
        );
    }
  }

  Widget _review() {
    final plan = _plan!;
    if (_found == 0) {
      return const Text(
          'In deinen Kontakten ist bei niemandem ein Geburtstag eingetragen.',
          style: Nl.body);
    }
    return ListView(
      children: [
        CountdownHero(
          lead: 'In deinen Kontakten stehen',
          number: '$_found',
          caption: 'Geburtstage',
          color: Nl.accent,
        ),
        const SizedBox(height: Nl.s5),
        _summaryRow('Neu', plan.toInsert.length),
        _summaryRow('Schon vorhanden, wird ergänzt', plan.toMerge.length),
        _summaryRow('Mögliche Doppelte, bitte prüfen', plan.toReview.length),
        if (plan.skippedDuplicatesInSource > 0)
          _summaryRow('Doppelt in den Kontakten, übersprungen',
              plan.skippedDuplicatesInSource),
        if (plan.toReview.isNotEmpty) ...[
          const SizedBox(height: Nl.s5),
          const SectionLabel('Dieselbe Person?'),
          const SizedBox(height: Nl.s2),
          for (var i = 0; i < plan.toReview.length; i++) _pair(i),
        ],
        const SizedBox(height: Nl.s5),
        const Text(
          'Gelesen werden nur Name, Geburtstag, Telefonnummer, E-Mail und Foto. Bestehende Profile und Notizen werden nie überschrieben.',
          style: Nl.caption,
        ),
        const SizedBox(height: Nl.s5),
        FilledButton(
          onPressed: plan.total == 0 ? null : _apply,
          child: Text('${plan.total} übernehmen'),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, int count) => Container(
        padding: const EdgeInsets.symmetric(vertical: Nl.s3),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Nl.divider))),
        child: Row(children: [
          Expanded(child: Text(label, style: Nl.bodySmall)),
          Text('$count', style: Nl.numberList),
        ]),
      );

  Widget _pair(int i) {
    final pair = _plan!.toReview[i];
    final same = _mergeReviewed.contains(i);
    String describe(Candidate c) =>
        '${c.fullName} · ${c.day}. ${monthNames[c.month - 1]}${c.year != null ? ' ${c.year}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: Nl.s3),
      child: NlCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kontakt: ${describe(pair.incoming)}', style: Nl.bodySmall),
            Text('In der App: ${describe(pair.existing)}', style: Nl.bodySmall),
            const SizedBox(height: Nl.s3),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Dieselbe')),
                ButtonSegment(value: false, label: Text('Zwei Personen')),
              ],
              selected: {same},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                if (s.first) {
                  _mergeReviewed.add(i);
                } else {
                  _mergeReviewed.remove(i);
                }
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Geburtstage aus deinen Kontakten übernehmen', style: Nl.title),
        const SizedBox(height: Nl.s3),
        const Text(
          'Die App liest nur Kontakte mit eingetragenem Geburtstag. Alles bleibt auf deinem Handy. Doppelte erkennt die App und fragt nach, wenn sie unsicher ist.',
          style: Nl.body,
        ),
        const Spacer(),
        FilledButton(onPressed: onStart, child: const Text('Kontakte lesen')),
      ],
    );
  }
}
