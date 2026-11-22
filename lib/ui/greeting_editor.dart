import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/ai_service.dart';
import '../data/database.dart';
import '../data/greeting_service.dart';
import '../data/share_bridge.dart';
import '../domain/birthday.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'motion.dart';
import 'widgets.dart';

/// Everything for one person's next birthday greeting: text (AI drafts,
/// own writing, rewrites, paste), a card image (prompt for ChatGPT, image
/// back from ChatGPT or the gallery) and the time it goes out.
class GreetingEditor extends StatefulWidget {
  const GreetingEditor({
    super.key,
    required this.person,
    this.incoming,
    this.autoGenerate = true,
  });
  final Person person;

  /// Text or image shared from another app, to put into this greeting.
  final SharedIn? incoming;

  /// Write drafts right away when there is no text yet.
  final bool autoGenerate;

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
  var _loaded = false;
  var _variants = <GreetingVariant>[];
  var _selected = -1;
  var _busy = false;
  var _busyPrompt = false;
  var _promptOpen = false;
  String? _error;
  var _time = const TimeOfDay(hour: 9, minute: 0);

  Person get p => widget.person;
  AppDatabase get db => AppScope.of(context);
  String? get _image => _greeting?.imagePath;
  String? get _prompt => _greeting?.imagePrompt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    var g = await db.greetingFor(p.id, _next.date.year);
    final inc = widget.incoming;
    if (inc?.imagePath != null) {
      final path = await CardImages.store(p.id, _next.date.year,
          await File(inc!.imagePath!).readAsBytes(),
          extension: CardImages.extensionOf(inc.imagePath!));
      await CardImages.remove(g?.imagePath);
      g = await db.saveGreeting(
          personId: p.id,
          year: _next.date.year,
          channel: p.channel,
          imagePath: Value(path));
    }
    if (!mounted) return;
    setState(() {
      _greeting = g;
      _variants = GreetingVariant.listFromJson(g?.variants);
      _text.text = inc?.text ?? g?.draft ?? '';
      if (g?.scheduledAt != null) {
        _time = TimeOfDay(hour: g!.scheduledAt!.hour, minute: g.scheduledAt!.minute);
      }
    });
    if (inc?.text != null) {
      _selected = -1;
      await _saveDraft();
    } else if (widget.autoGenerate && inc == null && _text.text.trim().isEmpty) {
      _generate();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  // ---- Text

  Future<void> _generate({String? instruction}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final v = await AiService(db).generate(p,
          instruction: instruction, baseText: _text.text.trim());
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

  Future<void> _ownWish() async {
    final rewrite = _text.text.trim().isNotEmpty;
    final wish = await _ask(
      title: rewrite ? 'Wie umschreiben?' : 'Was soll rein?',
      hint: rewrite
          ? 'z. B. erwähne die Velotour im Sommer'
          : 'z. B. kurz, auf Mundart, mit Bezug aufs neue Haus',
      action: 'Schreiben',
    );
    if (wish != null) await _generate(instruction: wish);
  }

  Future<String?> _ask(
      {required String title, required String hint, required String action}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: Nl.title.copyWith(fontSize: 22)),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          style: Nl.body,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () {
                final v = c.text.trim();
                Navigator.pop(context, v.isEmpty ? null : v);
              },
              child: Text(action)),
        ],
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim() ?? '';
    if (t.isEmpty) {
      _snack('Die Zwischenablage ist leer.');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _text.text = t;
      _selected = -1;
    });
    await _saveDraft();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text.text.trim()));
    HapticFeedback.selectionClick();
    _snack('Text kopiert.');
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

  // ---- Card image

  Future<void> _makePrompt() async {
    setState(() {
      _busyPrompt = true;
      _error = null;
    });
    String prompt;
    try {
      prompt = await AiService(db).imagePrompt(p, greeting: _text.text);
    } on AiException catch (e) {
      // Without the AI: a solid prompt from the profile alone.
      prompt = AiService.fallbackImagePrompt(p);
      if (mounted) _snack('${e.message} Einfacher Prompt ohne KI erstellt.');
    }
    final g = await db.saveGreeting(
        personId: p.id,
        year: _next.date.year,
        channel: p.channel,
        imagePrompt: Value(prompt));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _greeting = g;
      _busyPrompt = false;
      _promptOpen = true;
    });
  }

  Future<void> _editPrompt() async {
    final c = TextEditingController(text: _prompt ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Bildprompt', style: Nl.title.copyWith(fontSize: 22)),
        content: TextField(
            controller: c, minLines: 6, maxLines: 14, style: Nl.bodySmall),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Übernehmen')),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    final g = await db.saveGreeting(
        personId: p.id, year: _next.date.year, channel: p.channel,
        imagePrompt: Value(v));
    if (mounted) setState(() => _greeting = g);
  }

  Future<void> _toChatGpt() async {
    final prompt = _prompt;
    if (prompt == null) return;
    await Clipboard.setData(ClipboardData(text: prompt));
    HapticFeedback.selectionClick();
    var ok = await ShareBridge.sendTextToApp('com.openai.chatgpt', prompt);
    if (!ok) {
      ok = await launchUrl(
          Uri.parse('https://chatgpt.com/?q=${Uri.encodeComponent(prompt)}'),
          mode: LaunchMode.externalApplication);
    }
    if (mounted) {
      _snack(ok
          ? 'Prompt ist auch kopiert. Fertiges Bild: Teilen › Geburtstage.'
          : 'Prompt kopiert. ChatGPT liess sich nicht öffnen.');
    }
  }

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final path = await CardImages.store(p.id, _next.date.year, bytes,
        extension: CardImages.extensionOf(file.name));
    await CardImages.remove(_image);
    final g = await db.saveGreeting(
        personId: p.id, year: _next.date.year, channel: p.channel,
        imagePath: Value(path));
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _greeting = g);
  }

  Future<void> _removeImage() async {
    await CardImages.remove(_image);
    final g = await db.saveGreeting(
        personId: p.id, year: _next.date.year, channel: p.channel,
        imagePath: const Value(null));
    if (mounted) setState(() => _greeting = g);
  }

  Future<void> _shareImage() async {
    final img = _image;
    if (img == null) return;
    await ShareBridge.share(text: '', imagePath: img);
  }

  // ---- Plan and send

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
    _snack('Geplant: ${formatLong(_when)}, ${_time.format(context)}');
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
      _snack('Keine Nummer oder E-Mail für diesen Kanal hinterlegt.');
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Nl.personColor(p.colorIndex, today: _next.isToday);
    final scheduled = _greeting?.status == GreetingStatus.scheduled;
    final sent = _greeting?.status == GreetingStatus.sent;
    final hasText = _text.text.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s4, Nl.s5, Nl.s6),
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
                    Text(fullName(p),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: Nl.s6),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Nl.s4),
                child: NlCard(
                    child: Text(_error!,
                        style: Nl.body.copyWith(color: Nl.dangerInk))),
              ),

            // ---------------------------------------------------- Text
            const SectionLabel('Text'),
            const SizedBox(height: Nl.s3),
            if (_variants.length > 1) ...[
              SizedBox(
                height: 40,
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
                      selectedColor: color.withValues(alpha: 0.16),
                      side: BorderSide(color: on ? color : Nl.borderIcon),
                      labelStyle:
                          Nl.caption.copyWith(color: on ? Nl.ink : Nl.inkSoft),
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selected = i;
                          _text.text = _variants[i].text;
                        });
                        _saveDraft();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: Nl.s3),
            ],
            Container(
              decoration: BoxDecoration(
                color: Nl.surface,
                borderRadius: BorderRadius.circular(Nl.rL),
                border: Border.all(color: Nl.border),
              ),
              padding: const EdgeInsets.fromLTRB(Nl.s4, Nl.s3, Nl.s2, Nl.s1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: kEase,
                    child: _busy
                        ? const Padding(
                            padding: EdgeInsets.only(right: Nl.s2, top: Nl.s2),
                            child: _Writing(key: ValueKey('busy')),
                          )
                        : TextField(
                            key: const ValueKey('text'),
                            controller: _text,
                            minLines: 4,
                            maxLines: 14,
                            style: Nl.draft.copyWith(fontSize: 21, height: 30 / 21),
                            decoration: const InputDecoration(
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: 'Selbst schreiben, einfügen oder schreiben lassen …',
                            ),
                            onChanged: (_) => setState(() => _selected = -1),
                            onTapOutside: (_) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              _saveDraft();
                            },
                          ),
                  ),
                  const SizedBox(height: Nl.s2),
                  Row(
                    children: [
                      _ToolButton(
                          icon: Icons.content_paste,
                          label: 'Einfügen',
                          onTap: _busy ? null : _paste),
                      _ToolButton(
                          icon: Icons.copy_outlined,
                          label: 'Kopieren',
                          onTap: hasText ? _copy : null),
                      const Spacer(),
                      if (hasText)
                        IconButton(
                          tooltip: 'Leeren',
                          icon: const Icon(Icons.close, size: 18, color: Nl.muted),
                          onPressed: () {
                            setState(() {
                              _text.clear();
                              _selected = -1;
                            });
                            _saveDraft();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Nl.s3),
            Wrap(
              spacing: Nl.s2,
              runSpacing: Nl.s2,
              children: [
                _Chip(
                  icon: Icons.auto_awesome_outlined,
                  label: hasText ? 'Neue Entwürfe' : 'Schreiben lassen',
                  strong: true,
                  onTap: _busy ? null : () => _generate(),
                ),
                _Chip(
                  icon: Icons.edit_outlined,
                  label: 'Eigener Wunsch',
                  onTap: _busy ? null : _ownWish,
                ),
                if (hasText)
                  for (final (label, instruction) in const [
                    ('Wärmer', 'herzlicher und wärmer'),
                    ('Kürzer', 'deutlich kürzer'),
                    ('Frecher', 'frecher und verspielter'),
                    ('Mundart', 'auf Schweizerdeutsch (Mundart)'),
                    ('Förmlicher', 'etwas förmlicher'),
                  ])
                    _Chip(
                      label: label,
                      onTap: _busy ? null : () => _generate(instruction: instruction),
                    ),
              ],
            ),

            // ---------------------------------------------------- Card
            const SizedBox(height: Nl.s6),
            const SectionLabel('Karte'),
            const SizedBox(height: Nl.s3),
            if (_image != null) ...[
              _CardImage(
                path: _image!,
                onReplace: _pickImage,
                onRemove: _removeImage,
                onShare: _shareImage,
              ),
              const SizedBox(height: Nl.s3),
            ],
            NlCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busyPrompt)
                    const _Writing(label: 'Schreibe den Bildprompt …')
                  else if (_prompt == null) ...[
                    Text('Karte mit ChatGPT gestalten',
                        style: Nl.body.copyWith(color: Nl.ink)),
                    const SizedBox(height: Nl.s1),
                    Text(
                      'Die App schreibt einen Bildprompt aus dem Profil. Du öffnest ihn in ChatGPT und schickst das fertige Bild zurück.',
                      style: Nl.bodySmall,
                    ),
                    const SizedBox(height: Nl.s4),
                    OutlinedButton.icon(
                      onPressed: _makePrompt,
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Bildprompt schreiben'),
                    ),
                  ] else ...[
                    GestureDetector(
                      onTap: () => setState(() => _promptOpen = !_promptOpen),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: kEase,
                        alignment: Alignment.topCenter,
                        child: Text(
                          _prompt!,
                          maxLines: _promptOpen ? null : 4,
                          overflow: _promptOpen ? null : TextOverflow.fade,
                          style: Nl.bodySmall.copyWith(color: Nl.inkSoft),
                        ),
                      ),
                    ),
                    const SizedBox(height: Nl.s2),
                    Row(
                      children: [
                        _ToolButton(
                            icon: _promptOpen ? Icons.unfold_less : Icons.unfold_more,
                            label: _promptOpen ? 'Weniger' : 'Ganz',
                            onTap: () => setState(() => _promptOpen = !_promptOpen)),
                        _ToolButton(
                            icon: Icons.edit_outlined,
                            label: 'Ändern',
                            onTap: _editPrompt),
                        _ToolButton(
                            icon: Icons.refresh, label: 'Neu', onTap: _makePrompt),
                      ],
                    ),
                    const SizedBox(height: Nl.s3),
                    FilledButton.icon(
                      onPressed: _toChatGpt,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('In ChatGPT öffnen'),
                    ),
                  ],
                  const SizedBox(height: Nl.s2),
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: Text(_image == null ? 'Bild aus Galerie' : 'Anderes Bild'),
                  ),
                  const SizedBox(height: Nl.s2),
                  Text(
                    'Oder in ChatGPT direkt beim Bild: Teilen › Geburtstage.',
                    textAlign: TextAlign.center,
                    style: Nl.caption,
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------- Plan
            const SizedBox(height: Nl.s6),
            const SectionLabel('Senden'),
            const SizedBox(height: Nl.s3),
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
                                  ? 'Geplant: Erinnerung mit fertigem Gruss'
                                  : 'Zu dieser Zeit kommt der fertige Gruss',
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
            const SizedBox(height: Nl.s4),
            if (scheduled)
              OutlinedButton(onPressed: _unplan, child: const Text('Planung aufheben'))
            else
              FilledButton(
                onPressed: _busy || !hasText ? null : _plan,
                child: Text('Planen für ${_time.format(context)}'),
              ),
            const SizedBox(height: Nl.s2),
            TextButton(
              onPressed: _busy || !hasText ? null : _sendNow,
              child: Text(
                  'Jetzt senden per ${Channels.label(p.channel)}${_image != null ? ' mit Karte' : ''}'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small text-and-icon button inside a card.
class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? Nl.borderControl : Nl.inkSoft;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Nl.rS),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Nl.s2, vertical: Nl.s2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 6),
            Text(label, style: Nl.caption.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

/// Pill for the AI actions under the text.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.icon, this.strong = false});
  final String label;
  final IconData? icon;
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null
        ? Nl.borderControl
        : strong
            ? Nl.accent
            : Nl.inkSoft;
    return PressScale(
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: Nl.s3 + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: strong ? Nl.accent.withValues(alpha: 0.10) : null,
            border: Border.all(
                color: strong ? Nl.accent.withValues(alpha: 0.5) : Nl.borderIcon),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: Nl.caption.copyWith(color: fg, fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card image with its actions.
class _CardImage extends StatelessWidget {
  const _CardImage({
    required this.path,
    required this.onReplace,
    required this.onRemove,
    required this.onShare,
  });
  final String path;
  final VoidCallback onReplace;
  final VoidCallback onRemove;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Nl.rL),
      child: Stack(
        children: [
          Image.file(
            File(path),
            width: double.infinity,
            fit: BoxFit.fitWidth,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Container(
              height: 160,
              color: Nl.surface,
              alignment: Alignment.center,
              child: Text('Bild nicht gefunden', style: Nl.caption),
            ),
          ),
          Positioned(
            right: Nl.s3,
            bottom: Nl.s3,
            child: Row(
              children: [
                _ImageAction(icon: Icons.ios_share, tooltip: 'Bild teilen oder speichern', onTap: onShare),
                const SizedBox(width: Nl.s2),
                _ImageAction(icon: Icons.swap_horiz, tooltip: 'Ersetzen', onTap: onReplace),
                const SizedBox(width: Nl.s2),
                _ImageAction(icon: Icons.delete_outline, tooltip: 'Entfernen', onTap: onRemove),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageAction extends StatelessWidget {
  const _ImageAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Material(
              color: Nl.bg.withValues(alpha: 0.45),
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(icon, size: 18, color: Nl.ink),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Placeholder while the AI writes: three soft lines that shimmer.
class _Writing extends StatefulWidget {
  const _Writing({super.key, this.label = 'Schreibe drei Entwürfe …'});
  final String label;

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
            Text(widget.label, style: Nl.caption),
          ],
        ),
      );
}
