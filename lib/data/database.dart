import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Channels a greeting can go out on.
abstract final class Channels {
  static const whatsapp = 'whatsapp';
  static const sms = 'sms';
  static const email = 'email';
  static const other = 'other';

  static const all = [whatsapp, sms, email, other];

  static String label(String channel) => switch (channel) {
        whatsapp => 'WhatsApp',
        sms => 'SMS',
        email => 'E-Mail',
        _ => 'Anderer Kanal',
      };
}

@DataClassName('Person')
class People extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().withDefault(const Constant(''))();
  TextColumn get nickname => text().nullable()();
  IntColumn get birthDay => integer()();
  IntColumn get birthMonth => integer()();
  IntColumn get birthYear => integer().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  BlobColumn get photo => blob().nullable()();

  /// Id of the phone contact this person was imported from.
  TextColumn get contactId => text().nullable()();
  TextColumn get channel =>
      text().withDefault(const Constant(Channels.whatsapp))();

  // Profile: raw material for personal greetings (Phase 3).
  TextColumn get relation => text().nullable()();
  TextColumn get tone => text().nullable()();
  TextColumn get language => text().nullable()();
  TextColumn get insiders => text().withDefault(const Constant(''))();

  /// Index into the person colour palette.
  IntColumn get colorIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Note')
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get personId =>
      integer().references(People, #id, onDelete: KeyAction.cascade)();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Sent and drafted greetings (filled from Phase 3 on).
@DataClassName('Greeting')
class Greetings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get personId =>
      integer().references(People, #id, onDelete: KeyAction.cascade)();
  IntColumn get year => integer()();
  TextColumn get draft => text().nullable()();
  TextColumn get sentText => text().nullable()();
  TextColumn get channel => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [People, Notes, Greetings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'geburtstage'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Stream<List<Person>> watchPeople() =>
      (select(people)..orderBy([(p) => OrderingTerm.asc(p.firstName)])).watch();

  Future<List<Person>> allPeople() => select(people).get();

  Stream<Person?> watchPerson(int id) =>
      (select(people)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<int> addPerson(PeopleCompanion entry) async {
    final count = (await select(people).get()).length;
    return into(people).insert(entry.copyWith(colorIndex: Value(count % 3)));
  }

  Future<void> savePerson(Person person) => update(people).replace(person);

  Future<void> deletePerson(int id) =>
      (delete(people)..where((p) => p.id.equals(id))).go();

  Stream<List<Note>> watchNotes(int personId) => (select(notes)
        ..where((n) => n.personId.equals(personId))
        ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
      .watch();

  Future<void> addNote(int personId, String body) =>
      into(notes).insert(NotesCompanion.insert(personId: personId, body: body));

  Future<void> deleteNote(int id) =>
      (delete(notes)..where((n) => n.id.equals(id))).go();

  Future<List<Note>> allNotes() => select(notes).get();

  /// Replaces all data in one transaction (used by backup restore).
  Future<void> replaceAll(
      List<PeopleCompanion> newPeople, List<NotesCompanion> newNotes) {
    return transaction(() async {
      await delete(greetings).go();
      await delete(notes).go();
      await delete(people).go();
      await batch((b) {
        b.insertAll(people, newPeople);
        b.insertAll(notes, newNotes);
      });
    });
  }
}
