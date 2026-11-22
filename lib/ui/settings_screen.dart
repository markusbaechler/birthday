import 'package:flutter/material.dart';

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
      padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s6, Nl.s5, Nl.s5),
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
        const SectionLabel('In Arbeit'),
        const SizedBox(height: Nl.s2),
        const Text(
          'Phase 2: zuverlässige Erinnerungen. Phase 3: persönliche Glückwünsche. Phase 4: automatischer Versand per SMS.',
          style: Nl.bodySmall,
        ),
        const SizedBox(height: Nl.s5),
        const Text('Version 0.1.0', style: Nl.caption),
      ],
    );
  }
}
