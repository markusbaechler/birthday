import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ai_service.dart';
import '../data/database.dart';
import '../data/greeting_service.dart';
import '../domain/birthday.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'motion.dart';
import 'widgets.dart';

/// Write, choose, adjust and plan the greeting for one person's next
/// birthday. Three AI variants, quick rewrites, free editing, a time.
class GreetingEditor extends StatefulWidget {
  const GreetingEditor({super.key, required this.person});
  final Person person;

  @override
  State<GreetingEditor> createState() => _GreetingEditorState();
}

class _GreetingEditorState extends State<GreetingEditor> {
  final _text = TextEditingController();
  late final NextBirthday _next = nextBirthday(
      day: widget.person.birthDay,
      month: widget.person.birthMonth,
      year: widget.person.birthYear,
      today: DateTime.now());
  Greeting? _greeting;
  var _variants = <GreetingVariant>[];
  var _selected = -1;
  var _busy = false;
  String? _error;
  var _time = const TimeOfDay(hour: 9, minute: 0);

  Person get p => widget.person;
  AppDatabase get db => AppScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_greeting == null) _load();
  }

  Future<void> _load() async {
    final g = await db.greetingFor(p.id, _next.date.year);
    if (!mounted) return;
    setState(() {
      _greeting = g;
      _variants = GreetingVariant.listFromJson(g?.variants);
      _text.text = g?.draft ?? '';
      if (g?.scheduledAt != null) {
        _time = TimeOfDay(hour: g!.scheduledAt!.hour, minute: g.scheduledAt!.minute);
      }
    });
    if (g == null || (g.draft ?? '').isEmpty) _generate();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _generate({String? instruction}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final v = await AiService(db).generate(p,
          instruction: instruction,
          baseText: instruction == null ? null : _text.text.trim());
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _variants = v;
        _selected = 0;
        _text.text = v.first.text;
      });
      await _saveDraft();
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDraft() async {
    final g = await db.saveGreeting(
      personId: p.id,
      year: _next.date.year,
      channel: p.channel,
      draft: Value(_text.text.trim()),
      variants: Value(GreetingVariant.listToJson(_variants)),
    );
    if (mounted) setState(() => _greeting = g);
  }

  DateTime get _when => DateTime(_next.date.year, _next.date.month,
      _next.date.day, _time.hour, _time.minute);

  Future<void> _plan() async {
    if (_text.text.trim().isEmpty) return;
    final svc = GreetingService.instance;
    await svc.requestPermissions();
    final g = await db.saveGreeting(
      personId: p.id,
      year: _next.date.year,
      channel: p.channel,
      draft: Value(_text.text.trim()),
      status: const Value(GreetingStatus.scheduled),
      scheduledAt: Value(_when),
    );
    await svc.schedule(g, p);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => _greeting = g);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Geplant: ${formatLong(_when)}, ${_time.format(context)}')));
  }

  Future<void> _unplan() async {
    final g = _greeting;
    if (g == null) return;
    await GreetingService.instance.cancel(g.id);
    final updated = await db.saveGreeting(
      personId: p.id,
      year: g.year,
      channel: p.channel,
      status: const Value(GreetingStatus.draft),
      scheduledAt: const Value(null),
    );
    if (mounted) setState(() => _greeting = updated);
  }

  Future<void> _sendNow() async {
    await _saveDraft();
    final g = _greeting;
    if (g == null) return;
    final ok = await GreetingService.instance.send(g, p);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Keine Nummer oder E-Mail für diesen Kanal hinterlegt.')));
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Nl.personColor(p.colorIndex, today: _next.isToday);
    final scheduled = _greeting?.status == GreetingStatus.scheduled;
    final sent = _greeting?.status == GreetingStatus.sent;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s5, Nl.s5, Nl.s6),
          children: [
            Row(children: [
              RoundIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Zurück',
                  onPressed: () async {
                    await _saveDraft();
                    if (context.mounted) Navigator.of(context).pop();
                  }),
              const SizedBox(width: Nl.s4),
              PersonRing(person: p, size: 44, today: _next.isToday),
              const SizedBox(width: Nl.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gruss für ${displayName(p)}',
                        style: Nl.body.copyWith(color: Nl.ink)),
                    Text(
                      [
                        if (_next.turning != null) 'wird ${_next.turning}',
                        formatShort(_next.date),
                        Channels.label(p.channel),
                      ].join(' · '),
                      style: Nl.caption,
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: Nl.s5),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Nl.s4),
                child: NlCard(
                    child: Text(_error!,
                        style: Nl.body.copyWith(color: Nl.dangerInk))),
              ),
            if (_variants.length > 1) ...[
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _variants.length,
                  separatorBuilder: (_, __) => const SizedBox(width: Nl.s2),
                  itemBuilder: (context, i) {
                    final on = i == _selected;
                    return ChoiceChip(
                      label: Text(_variants[i].title.isEmpty
                          ? 'Variante ${i + 1}'
                          : _variants[i].title),
                      selected: on,
                      showCheckmark: false,
                      selectedColor: color.withValues(alpha: 0.18),
                      side: BorderSide(color: on ? color : Nl.borderIcon),
                      labelStyle: Nl.caption.copyWith(color: on ? Nl.ink : Nl.inkSoft),
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selected = i;
                          _text.text = _variants[i].text;
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: Nl.s4),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: kEase,
              child: _busy
                  ? const _Writing(key: ValueKey('busy'))
                  : TextField(
                      key: const ValueKey('text'),
                      controller: _text,
                      minLines: 4,
                      maxLines: 12,
                      style: Nl.draft,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Dein Gruss …',
                      ),
                      onChanged: (_) => setState(() => _selected = -1),
                    ),
            ),
            const SizedBox(height: Nl.s3),
            Wrap(
              spacing: Nl.s2,
              runSpacing: Nl.s2,
              children: [
                for (final (label, instruction) in const [
                  ('Neu', null),
                  ('Wärmer', 'herzlicher und wärmer'),
                  ('Kürzer', 'deutlich kürzer'),
                  ('Frecher', 'frecher und verspielter'),
                  ('Auf Mundart', 'auf Schweizerdeutsch (Mundart)'),
                  ('Förmlicher', 'etwas förmlicher'),
                ])
                  ActionChip(
                    label: Text(label),
                    labelStyle: Nl.caption.copyWith(color: Nl.inkSoft),
                    side: const BorderSide(color: Nl.borderIcon),
                    onPressed: _busy
                        ? null
                        : () => _generate(
                            instruction: _text.text.trim().isEmpty ? null : instruction),
                  ),
              ],
            ),
            const SizedBox(height: Nl.s6),
            const SectionLabel('Planen'),
            const SizedBox(height: Nl.s2),
            NlCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatLong(_when), style: Nl.body.copyWith(color: Nl.ink)),
                        Text(
                          sent
                              ? 'Gesendet'
                              : scheduled
                                  ? 'Geplant: Erinnerung mit fertigem Text'
                                  : 'Zur gewählten Zeit kommt der fertige Text',
                          style: Nl.caption.copyWith(
                              color: scheduled ? Nl.personGreen : Nl.muted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: _time);
                      if (t == null) return;
                      setState(() => _time = t);
                      if (scheduled) await _plan();
                    },
                    child: Text(_time.format(context),
                        style: Nl.display(26, weight: 300, color: color)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Nl.s5),
            if (scheduled)
              OutlinedButton(onPressed: _unplan, child: const Text('Planung aufheben'))
            else
              FilledButton(
                onPressed: _busy || _text.text.trim().isEmpty ? null : _plan,
                child: Text('Planen für ${_time.format(context)}'),
              ),
            const SizedBox(height: Nl.s2),
            TextButton(
              onPressed: _busy || _text.text.trim().isEmpty ? null : _sendNow,
              child: Text('Jetzt senden per ${Channels.label(p.channel)}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder while the AI writes: three soft lines that shimmer.
class _Writing extends StatefulWidget {
  const _Writing({super.key});

  @override
  State<_Writing> createState() => _WritingState();
}

class _WritingState extends State<_Writing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, w) in const [(0, 1.0), (1, 0.86), (2, 0.6)].indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Nl.s3),
                child: FractionallySizedBox(
                  widthFactor: w.$2,
                  child: Container(
                    height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      gradient: LinearGradient(
                        begin: Alignment(-1 + 3 * ((_c.value + i * 0.15) % 1) - 1, 0),
                        end: Alignment(1 + 3 * ((_c.value + i * 0.15) % 1) - 1, 0),
                        colors: const [Nl.surface, Color(0xFF2A2433), Nl.surface],
                      ),
                    ),
                  ),
                ),
              ),
            Text('Schreibe drei Entwürfe …', style: Nl.caption),
          ],
        ),
      );
}
