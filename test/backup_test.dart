import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geburtstage/data/backup_service.dart';
import 'package:geburtstage/data/database.dart';

void main() {
  SharedPreferences.setMockInitialValues({});
  test('backup round trip keeps people, notes and greetings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final id = await db.addPerson(PeopleCompanion.insert(
      firstName: 'Silvia',
      lastName: const Value('Meier'),
      birthDay: 28,
      birthMonth: 11,
      birthYear: const Value(1982),
    ));
    await db.saveGreeting(
      personId: id,
      year: 2026,
      channel: Channels.whatsapp,
      draft: const Value('Alles Gute!'),
      status: const Value(GreetingStatus.scheduled),
      scheduledAt: Value(DateTime(2026, 11, 28, 9)),
      imagePrompt: const Value('Prompt'),
    );

    final service = BackupService(db);
    // Through JSON, as a real file would go.
    final data = jsonDecode(jsonEncode(await service.export())) as Map<String, dynamic>;
    await db.replaceAll(const [], const []);
    expect(await db.allPeople(), isEmpty);

    expect(await service.restore(data), 1);
    final g = await db.greetingFor(id, 2026);
    expect(g?.draft, 'Alles Gute!');
    expect(g?.status, GreetingStatus.scheduled);
    expect(g?.scheduledAt, DateTime(2026, 11, 28, 9));
    expect(g?.imagePrompt, 'Prompt');
    await db.close();
  });
}
