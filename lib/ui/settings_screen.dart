import 'package:flutter/material.dart';

import '../data/ai_service.dart';
import '../data/backup_service.dart';
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
        row('Sicherung erstellen', 'Als Datei teilen, z. B. in Google Drive',
            'Teilen', () => BackupService(db).shareBackup()),
        row('Sicherung wiederherstellen', 'Ersetzt alle Daten in der App',
            'Wählen', () => _restore(context)),
        const SizedBox(height: Nl.s6),
        const SectionLabel('Glückwunsch-KI'),
        const SizedBox(height: Nl.s2),
        const _ApiKeyRow(),
        const SizedBox(height: Nl.s6),
        const SectionLabel('In Arbeit'),
        const SizedBox(height: Nl.s2),
        const Text(
          'Als Nächstes: automatischer Versand per SMS für Personen ohne WhatsApp, Erinnerungen ohne geplanten Gruss.',
          style: Nl.bodySmall,
        ),
        const SizedBox(height: Nl.s5),
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
