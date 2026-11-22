import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../domain/birthday.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'widgets.dart';

/// Create or edit a person. Without [person] a new one is created.
class PersonEditScreen extends StatefulWidget {
  const PersonEditScreen({super.key, this.person});
  final Person? person;

  @override
  State<PersonEditScreen> createState() => _PersonEditScreenState();
}

class _PersonEditScreenState extends State<PersonEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.person?.firstName);
  late final _last = TextEditingController(text: widget.person?.lastName);
  late final _nick = TextEditingController(text: widget.person?.nickname);
  late final _year =
      TextEditingController(text: widget.person?.birthYear?.toString());
  late final _phone = TextEditingController(text: widget.person?.phone);
  late final _email = TextEditingController(text: widget.person?.email);
  late final _relation = TextEditingController(text: widget.person?.relation);
  late final _tone = TextEditingController(text: widget.person?.tone);
  late final _language = TextEditingController(text: widget.person?.language);
  late final _insiders = TextEditingController(text: widget.person?.insiders);
  late int _day = widget.person?.birthDay ?? 1;
  late int _month = widget.person?.birthMonth ?? 1;
  late String _channel = widget.person?.channel ?? Channels.whatsapp;

  bool get _isNew => widget.person == null;

  @override
  void dispose() {
    for (final c in [
      _first, _last, _nick, _year, _phone, _email, _relation, _tone,
      _language, _insiders
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final db = AppScope.of(context);
    final year = int.tryParse(_year.text.trim());
    if (_isNew) {
      await db.addPerson(PeopleCompanion.insert(
        firstName: _first.text.trim(),
        lastName: Value(_last.text.trim()),
        nickname: Value(_opt(_nick)),
        birthDay: _day,
        birthMonth: _month,
        birthYear: Value(year),
        phone: Value(_opt(_phone)),
        email: Value(_opt(_email)),
        channel: Value(_channel),
        relation: Value(_opt(_relation)),
        tone: Value(_opt(_tone)),
        language: Value(_opt(_language)),
        insiders: Value(_insiders.text.trim()),
      ));
    } else {
      await db.savePerson(widget.person!.copyWith(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        nickname: Value(_opt(_nick)),
        birthDay: _day,
        birthMonth: _month,
        birthYear: Value(year),
        phone: Value(_opt(_phone)),
        email: Value(_opt(_email)),
        channel: _channel,
        relation: Value(_opt(_relation)),
        tone: Value(_opt(_tone)),
        language: Value(_opt(_language)),
        insiders: _insiders.text.trim(),
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Person löschen?', style: Nl.title),
        content: Text(
            '${fullName(widget.person!)} wird mit allen Notizen gelöscht. Das lässt sich nicht rückgängig machen.',
            style: Nl.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Löschen',
                  style: TextStyle(color: Nl.dangerInk))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AppScope.of(context).deletePerson(widget.person!.id);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _field(TextEditingController c, String label,
          {TextInputType? type, int maxLines = 1, String? Function(String?)? validator}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: Nl.s3),
        child: TextFormField(
          controller: c,
          keyboardType: type,
          maxLines: maxLines,
          minLines: 1,
          style: Nl.body,
          decoration: InputDecoration(labelText: label),
          validator: validator,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s5, Nl.s5, Nl.s6),
            children: [
              Row(
                children: [
                  RoundIconButton(
                    icon: Icons.close,
                    tooltip: 'Abbrechen',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: Nl.s4),
                  Expanded(
                    child: Text(_isNew ? 'Neue Person' : 'Bearbeiten',
                        style: Nl.lead),
                  ),
                ],
              ),
              const SizedBox(height: Nl.s5),
              _field(_first, 'Vorname',
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Bitte einen Vornamen' : null),
              _field(_last, 'Nachname'),
              _field(_nick, 'Rufname (optional)'),
              const SizedBox(height: Nl.s3),
              const SectionLabel('Geburtstag'),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _day,
                      decoration: const InputDecoration(labelText: 'Tag'),
                      items: [
                        for (var d = 1; d <= 31; d++)
                          DropdownMenuItem(value: d, child: Text('$d'))
                      ],
                      onChanged: (v) => setState(() => _day = v ?? _day),
                    ),
                  ),
                  const SizedBox(width: Nl.s4),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: _month,
                      decoration: const InputDecoration(labelText: 'Monat'),
                      items: [
                        for (var m = 1; m <= 12; m++)
                          DropdownMenuItem(
                              value: m, child: Text(monthNames[m - 1]))
                      ],
                      onChanged: (v) => setState(() => _month = v ?? _month),
                    ),
                  ),
                  const SizedBox(width: Nl.s4),
                  Expanded(
                    child: TextFormField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      style: Nl.body,
                      decoration: const InputDecoration(labelText: 'Jahr'),
                      validator: (v) {
                        final y = (v ?? '').trim().isEmpty
                            ? null
                            : int.tryParse(v!.trim());
                        if ((v ?? '').trim().isNotEmpty && y == null) {
                          return 'Zahl';
                        }
                        return isValidBirthday(_day, _month, y)
                            ? null
                            : 'Datum prüfen';
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Nl.s5),
              const SectionLabel('Kontakt'),
              DropdownButtonFormField<String>(
                value: _channel,
                decoration: const InputDecoration(labelText: 'Glückwunsch per'),
                items: [
                  for (final c in Channels.all)
                    DropdownMenuItem(value: c, child: Text(Channels.label(c)))
                ],
                onChanged: (v) => setState(() => _channel = v ?? _channel),
              ),
              const SizedBox(height: Nl.s3),
              _field(_phone, 'Telefon', type: TextInputType.phone),
              _field(_email, 'E-Mail', type: TextInputType.emailAddress),
              const SizedBox(height: Nl.s3),
              const SectionLabel('Für persönliche Grüsse'),
              _field(_relation, 'Beziehung (z. B. Bruder, Freundin)'),
              _field(_tone, 'Ton (z. B. herzlich, frech)'),
              _field(_language, 'Sprache (z. B. Mundart, Englisch)'),
              _field(_insiders, 'Insider und Erlebnisse', maxLines: 6),
              const SizedBox(height: Nl.s5),
              FilledButton(onPressed: _save, child: const Text('Speichern')),
              if (!_isNew) ...[
                const SizedBox(height: Nl.s2),
                OutlinedButton(
                  onPressed: _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Nl.dangerInk,
                    side: const BorderSide(color: Nl.dangerBorder),
                  ),
                  child: const Text('Person löschen'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
