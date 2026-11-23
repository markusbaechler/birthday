import 'package:flutter/material.dart';

import '../data/ai_service.dart';
import '../data/backup_service.dart';
import '../data/greeting_service.dart';
import '../data/share_bridge.dart';
import '../data/style_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../theme/tokens.dart';
import 'import_screen.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _restore(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = BackupService(AppScope.of(context));
    try {
      final data = await service.pickBackup();
      if (data == null || !context.mounted) return;
      final count = (data['people'] as List).length;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sicherung wiederherstellen?', style: Nl.title),
          content: Text(
            'Alle Daten in der App werden durch die Sicherung ersetzt ($count Personen).',
            style: Nl.body,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ersetzen',
                    style: TextStyle(color: Nl.dangerInk))),
          ],
        ),
      );
      if (ok != true) return;
      final restored = await service.restore(data);
      try {
        await GreetingService.instance.rescheduleAll();
        await GreetingService.instance.rescheduleReminders();
      } catch (_) {}
      messenger.showSnackBar(
          SnackBar(content: Text('$restored Personen wiederhergestellt.')));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Die Sicherung liess sich nicht lesen.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context);
    Widget row(String title, String sub, String action, VoidCallback onTap) =>
        Container(
          padding: const EdgeInsets.symmetric(vertical: Nl.s3),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Nl.divider))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Nl.body.copyWith(color: Nl.ink)),
                    Text(sub, style: Nl.caption),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: Nl.s4)),
                child: Text(action),
              ),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, 120),
      children: [
        const SectionLabel('Einstellungen'),
        const SizedBox(height: Nl.s5),
        const SectionLabel('Daten'),
        row('Kontakte übernehmen', 'Geburtstage aus dem Telefonbuch', 'Starten',
            () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ImportScreen()))),
        const _AutoBackupRow(),
        row('Sicherung teilen', 'Zusätzliche Kopie, z. B. in Google Drive',
            'Teilen', () => BackupService(db).shareBackup()),
        row('Sicherung wiederherstellen', 'Datei wählen; ersetzt alle Daten',
            'Wählen', () => _restore(context)),
        const SizedBox(height: Nl.s6),
        const SectionLabel('Glückwunsch-KI'),
        const SizedBox(height: Nl.s2),
        const _ApiKeyRow(),
        const _StyleRow(),
        const SizedBox(height: Nl.s6),
        const SectionLabel('Erinnerungen'),
        const SizedBox(height: Nl.s2),
        const _ReminderSection(),
        const SizedBox(height: Nl.s6),
        const Text('Version 0.1.0', style: Nl.caption),
      ],
    );
  }
}


class _ApiKeyRow extends StatefulWidget {
  const _ApiKeyRow();

  @override
  State<_ApiKeyRow> createState() => _ApiKeyRowState();
}

class _ApiKeyRowState extends State<_ApiKeyRow> {
  bool? _hasKey;

  @override
  void initState() {
    super.initState();
    Secrets.apiKey().then((k) {
      if (mounted) setState(() => _hasKey = k != null);
    });
  }

  Future<void> _edit() async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API-Schlüssel', style: Nl.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Schlüssel von console.anthropic.com (beginnt mit «sk-ant-»). Er bleibt verschlüsselt auf diesem Handy.',
              style: Nl.bodySmall,
            ),
            const SizedBox(height: Nl.s3),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              style: Nl.body,
              decoration: const InputDecoration(hintText: 'sk-ant-…'),
            ),
          ],
        ),
        actions: [
          if (_hasKey == true)
            TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('Entfernen', style: TextStyle(color: Nl.dangerInk))),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Prüfen und speichern')),
        ],
      ),
    );
    if (key == null) return;
    if (key.isEmpty) {
      await Secrets.setApiKey(null);
      if (mounted) setState(() => _hasKey = false);
      return;
    }
    final result = await AiService.testKey(key);
    // A valid key is kept even if e.g. credit is still missing.
    if (result.usable) await Secrets.setApiKey(key);
    if (!mounted) return;
    setState(() => _hasKey = result.usable || _hasKey == true);
    if (result.error == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Schlüssel funktioniert und ist gespeichert.')));
    } else {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result.usable ? 'Gespeichert, aber noch nicht bereit' : 'Nicht gespeichert'),
          content: SelectableText(result.error!),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: Nl.s3),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Nl.divider))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Anthropic API-Schlüssel', style: Nl.body.copyWith(color: Nl.ink)),
                  Text(
                    _hasKey == null
                        ? '…'
                        : _hasKey!
                            ? 'Hinterlegt, verschlüsselt'
                            : 'Fehlt: ohne Schlüssel keine Entwürfe',
                    style: Nl.caption.copyWith(
                        color: _hasKey == true ? Nl.personGreen : Nl.muted),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: _edit,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: Nl.s4)),
              child: Text(_hasKey == true ? 'Ändern' : 'Eintragen'),
            ),
          ],
        ),
      );
}


/// Reminder times, a health check of what Android allows, and a test.
class _ReminderSection extends StatefulWidget {
  const _ReminderSection();

  @override
  State<_ReminderSection> createState() => _ReminderSectionState();
}

class _ReminderSectionState extends State<_ReminderSection>
    with WidgetsBindingObserver {
  var _s = const ReminderSettings();
  bool? _notifications;
  bool? _exact;
  bool? _battery;
  int? _pending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from Android's settings: check again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = ReminderSettings.read(prefs);
    bool? n, e, b;
    int? pending;
    try {
      final st = await GreetingService.instance.status();
      n = st.notifications;
      e = st.exact;
      pending = await GreetingService.instance.pendingReminders();
      b = await ShareBridge.batteryUnrestricted();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _s = settings;
      _notifications = n;
      _exact = e;
      _battery = b;
      _pending = pending;
    });
  }

  Future<void> _save(ReminderSettings s) async {
    setState(() => _s = s);
    await s.write(await SharedPreferences.getInstance());
    await GreetingService.instance.rescheduleReminders();
    await _load();
  }

  Future<void> _pick(bool eve) async {
    final t = await showTimePicker(
        context: context,
        initialTime: eve
            ? TimeOfDay(hour: _s.eveHour, minute: _s.eveMinute)
            : TimeOfDay(hour: _s.dayHour, minute: _s.dayMinute));
    if (t == null) return;
    await _save(ReminderSettings(
      eve: _s.eve,
      eveHour: eve ? t.hour : _s.eveHour,
      eveMinute: eve ? t.minute : _s.eveMinute,
      day: _s.day,
      dayHour: eve ? _s.dayHour : t.hour,
      dayMinute: eve ? _s.dayMinute : t.minute,
    ));
  }

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    await GreetingService.instance.requestPermissions();
    await GreetingService.instance.scheduleTest();
    await _load();
    messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 6),
        content: Text(
            'Test kommt in 1 Minute. Jetzt den Bildschirm sperren und warten.')));
  }

  static String _hm(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Widget _timeRow(String title, String sub, bool on, String time,
          ValueChanged<bool> onToggle, VoidCallback onTime) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: Nl.s2),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Nl.divider))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Nl.body.copyWith(color: Nl.ink)),
                  Text(sub, style: Nl.caption),
                ],
              ),
            ),
            TextButton(
              onPressed: on ? onTime : null,
              child: Text(time,
                  style: Nl.display(22,
                      weight: 300, color: on ? Nl.accent : Nl.borderControl)),
            ),
            Switch(value: on, onChanged: onToggle),
          ],
        ),
      );

  Widget _check(String title, String fix, bool? ok, VoidCallback onFix) {
    final color = ok == null
        ? Nl.muted
        : ok
            ? Nl.personGreen
            : Nl.personAmber;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Nl.s2),
      child: Row(
        children: [
          Icon(
              ok == null
                  ? Icons.help_outline
                  : ok
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
              size: 20,
              color: color),
          const SizedBox(width: Nl.s3),
          Expanded(
              child: Text(title,
                  style: Nl.bodySmall.copyWith(color: Nl.inkSoft))),
          if (ok == false)
            TextButton(onPressed: onFix, child: Text(fix)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allGood =
        _notifications == true && _exact == true && _battery == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _timeRow(
          'Am Vorabend',
          'Zeit, um noch einen Gruss vorzubereiten',
          _s.eve,
          _hm(_s.eveHour, _s.eveMinute),
          (v) => _save(ReminderSettings(
              eve: v,
              eveHour: _s.eveHour,
              eveMinute: _s.eveMinute,
              day: _s.day,
              dayHour: _s.dayHour,
              dayMinute: _s.dayMinute)),
          () => _pick(true),
        ),
        _timeRow(
          'Am Geburtstag',
          'Entfällt, wenn ein Gruss geplant ist',
          _s.day,
          _hm(_s.dayHour, _s.dayMinute),
          (v) => _save(ReminderSettings(
              eve: _s.eve,
              eveHour: _s.eveHour,
              eveMinute: _s.eveMinute,
              day: v,
              dayHour: _s.dayHour,
              dayMinute: _s.dayMinute)),
          () => _pick(false),
        ),
        const SizedBox(height: Nl.s4),
        NlCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  allGood
                      ? 'Alles bereit für pünktliche Erinnerungen'
                      : 'Verlässlichkeit prüfen',
                  style: Nl.body.copyWith(color: Nl.ink)),
              const SizedBox(height: Nl.s2),
              _check('Benachrichtigungen erlaubt', 'Erlauben', _notifications,
                  () async {
                await GreetingService.instance.requestPermissions();
                if (!(await GreetingService.instance.status()).notifications) {
                  await ShareBridge.openAppSettings();
                }
                await _load();
              }),
              _check('Pünktlich auf die Minute', 'Erlauben', _exact, () async {
                await GreetingService.instance.requestPermissions();
                await _load();
              }),
              _check('Akku: App wird nicht schlafen gelegt', 'Beheben', _battery,
                  () async {
                await ShareBridge.requestBatteryUnrestricted();
              }),
              if (_pending != null)
                Padding(
                  padding: const EdgeInsets.only(top: Nl.s1),
                  child: Text('$_pending Erinnerungen sind eingeplant.',
                      style: Nl.caption),
                ),
              const SizedBox(height: Nl.s3),
              OutlinedButton.icon(
                onPressed: _test,
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Test in 1 Minute senden'),
              ),
              const SizedBox(height: Nl.s2),
              const Text(
                'Samsung: Falls der Test bei gesperrtem Bildschirm nicht kommt, in den Einstellungen unter Akku › Hintergrundnutzung «Geburtstage» bei «Nie in Standby» eintragen.',
                style: Nl.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}


/// State of the automatic backup, with a button to run it now.
class _AutoBackupRow extends StatefulWidget {
  const _AutoBackupRow();

  @override
  State<_AutoBackupRow> createState() => _AutoBackupRowState();
}

class _AutoBackupRowState extends State<_AutoBackupRow> {
  ({DateTime? at, String? where, String? error})? _last;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await BackupService.lastAuto();
    if (mounted) setState(() => _last = l);
  }

  Future<void> _now() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final ok = await BackupService(AppScope.of(context)).autoBackup(force: true);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? 'Gesichert in ${_last?.where ?? 'Download/Geburtstage'}.'
            : 'Sicherung fehlgeschlagen: ${_last?.error ?? 'keine Daten'}')));
  }

  @override
  Widget build(BuildContext context) {
    final l = _last;
    final at = l?.at;
    final failed = l?.error != null;
    final when = at == null
        ? 'Noch keine'
        : 'Zuletzt ${at.day}.${at.month}. ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Nl.s3),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Nl.divider))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Automatische Sicherung',
                    style: Nl.body.copyWith(color: Nl.ink)),
                Text(
                  failed
                      ? 'Fehlgeschlagen. $when'
                      : '$when · Ordner Download/Geburtstage, bleibt auch nach dem Löschen der App',
                  style: Nl.caption.copyWith(
                      color: failed ? Nl.dangerInk : Nl.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: Nl.s3),
          OutlinedButton(
            onPressed: _busy ? null : _now,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: Nl.s4)),
            child: Text(_busy ? '…' : 'Jetzt'),
          ),
        ],
      ),
    );
  }
}


/// «Mein Stil»: what the AI knows about how the sender writes.
class _StyleRow extends StatefulWidget {
  const _StyleRow();

  @override
  State<_StyleRow> createState() => _StyleRowState();
}

class _StyleRowState extends State<_StyleRow> {
  StyleProfile? _profile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final p = await StyleProfile.load(AppScope.of(context));
    if (mounted) setState(() => _profile = p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final own = p != null &&
        (p.note.trim().isNotEmpty || p.ownExamples.trim().isNotEmpty);
    final n = p?.learned.length ?? 0;
    final sub = [
      if (own) 'Eigene Angaben hinterlegt',
      n == 0
          ? 'Lernt, sobald du Grüsse anpasst und sendest'
          : 'Lernt aus $n ${n == 1 ? 'eigenen Gruss' : 'eigenen Grüssen'}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Nl.s3),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Nl.divider))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mein Stil', style: Nl.body.copyWith(color: Nl.ink)),
                Text(sub, style: Nl.caption),
              ],
            ),
          ),
          const SizedBox(width: Nl.s3),
          OutlinedButton(
            onPressed: p == null
                ? null
                : () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => StyleScreen(profile: p)));
                    await _load();
                  },
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: Nl.s4)),
            child: const Text('Anpassen'),
          ),
        ],
      ),
    );
  }
}

/// Edit the own style note and examples; see what the app has learned.
class StyleScreen extends StatefulWidget {
  const StyleScreen({super.key, required this.profile});
  final StyleProfile profile;

  @override
  State<StyleScreen> createState() => _StyleScreenState();
}

class _StyleScreenState extends State<StyleScreen> {
  late final _note = TextEditingController(text: widget.profile.note);
  late final _examples = TextEditingController(text: widget.profile.ownExamples);

  @override
  void dispose() {
    _note.dispose();
    _examples.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await StyleProfile.writeOwn(_note.text, _examples.text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s4, Nl.s5, Nl.s6),
          children: [
            Row(children: [
              RoundIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Zurück',
                  onPressed: () => Navigator.of(context).pop()),
              const SizedBox(width: Nl.s4),
              const Expanded(child: SectionLabel('Mein Stil')),
            ]),
            const SizedBox(height: Nl.s5),
            const Text('Damit Entwürfe nach dir klingen', style: Nl.title),
            const SizedBox(height: Nl.s2),
            const Text(
              'Die KI übernimmt den Stil, nicht den Inhalt. Je mehr echte Beispiele, desto näher an dir.',
              style: Nl.bodySmall,
            ),
            const SizedBox(height: Nl.s5),
            const SectionLabel('So schreibe ich'),
            const SizedBox(height: Nl.s2),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              style: Nl.body,
              decoration: const InputDecoration(
                  hintText:
                      'z. B. kurz und trocken, immer per Du, gern ein Mundart-Wort, kein Emoji, Schluss mit «Häbs guet»'),
            ),
            const SizedBox(height: Nl.s5),
            const SectionLabel('Beispiele von mir'),
            const SizedBox(height: Nl.s2),
            TextField(
              controller: _examples,
              minLines: 4,
              maxLines: 12,
              style: Nl.body,
              decoration: const InputDecoration(
                  hintText:
                      'Zwei bis fünf echte Grüsse von dir einfügen, z. B. aus WhatsApp kopiert. Einer pro Absatz.'),
            ),
            const SizedBox(height: Nl.s5),
            FilledButton(onPressed: _save, child: const Text('Speichern')),
            const SizedBox(height: Nl.s6),
            const SectionLabel('Automatisch gelernt'),
            const SizedBox(height: Nl.s2),
            if (p.learned.isEmpty)
              const Text(
                'Noch nichts. Die App lernt aus Grüssen, die du selbst geschrieben oder nach einem Entwurf angepasst und dann gesendet hast. Unverändert gesendete KI-Texte zählen nicht.',
                style: Nl.bodySmall,
              )
            else ...[
              for (final e in p.learned)
                Padding(
                  padding: const EdgeInsets.only(bottom: Nl.s3),
                  child: NlCard(
                      child: Text(e,
                          style: Nl.bodySmall.copyWith(color: Nl.inkSoft))),
                ),
              if (p.edits.isNotEmpty)
                Text(
                    '${p.edits.length} ${p.edits.length == 1 ? 'Korrektur' : 'Korrekturen'} an KI-Entwürfen fliessen zusätzlich ein.',
                    style: Nl.caption),
            ],
          ],
        ),
      ),
    );
  }
}
