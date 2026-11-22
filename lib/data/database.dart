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

/// Greeting status values.
abstract final class GreetingStatus {
  static const draft = 'draft';
  static const scheduled = 'scheduled';
  static const sent = 'sent';
}

/// One greeting per person and birthday year: drafted, scheduled, sent.
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

  /// When the reminder with the ready text fires (local time).
  DateTimeColumn get scheduledAt => dateTime().nullable()();

  /// Last generated variants as JSON ([{"title","text"}]).
  TextColumn get variants => text().nullable()();

  /// Prompt for an external image AI (e.g. ChatGPT) to design a card.
  TextColumn get imagePrompt => text().nullable()();

  /// The card image that goes out with the text (file in app storage).
  TextColumn get imagePath => text().nullable()();
}

@DriftDatabase(tables: [People, Notes, Greetings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'geburtstage'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(greetings, greetings.scheduledAt);
            await m.addColumn(greetings, greetings.variants);
          }
          if (from < 3) {
            await m.addColumn(greetings, greetings.imagePrompt);
            await m.addColumn(greetings, greetings.imagePath);
          }
        },
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

  // ---- Greetings

  Stream<List<Greeting>> watchGreetings() => select(greetings).watch();

  Future<Greeting?> greetingFor(int personId, int year) => (select(greetings)
        ..where((g) => g.personId.equals(personId) & g.year.equals(year))
        ..limit(1))
      .getSingleOrNull();

  Future<Greeting?> greetingById(int id) =>
      (select(greetings)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<List<Greeting>> scheduledGreetings() => (select(greetings)
        ..where((g) => g.status.equals(GreetingStatus.scheduled)))
      .get();

  Future<List<Greeting>> sentGreetingsFor(int personId) => (select(greetings)
        ..where((g) =>
            g.personId.equals(personId) & g.status.equals(GreetingStatus.sent))
        ..orderBy([(g) => OrderingTerm.desc(g.year)]))
      .get();

  /// Creates or updates the greeting of [personId] for [year].
  Future<Greeting> saveGreeting({
    required int personId,
    required int year,
    required String channel,
    Value<String?> draft = const Value.absent(),
    Value<String?> sentText = const Value.absent(),
    Value<String> status = const Value.absent(),
    Value<DateTime?> scheduledAt = const Value.absent(),
    Value<String?> variants = const Value.absent(),
    Value<String?> imagePrompt = const Value.absent(),
    Value<String?> imagePath = const Value.absent(),
  }) async {
    final existing = await greetingFor(personId, year);
    if (existing == null) {
      final id = await into(greetings).insert(GreetingsCompanion.insert(
        personId: personId,
        year: year,
        channel: channel,
        draft: draft,
        sentText: sentText,
        status: status,
        scheduledAt: scheduledAt,
        variants: variants,
        imagePrompt: imagePrompt,
        imagePath: imagePath,
      ));
      return (await greetingById(id))!;
    }
    await (update(greetings)..where((g) => g.id.equals(existing.id))).write(
      GreetingsCompanion(
        channel: Value(channel),
        draft: draft,
        sentText: sentText,
        status: status,
        scheduledAt: scheduledAt,
        variants: variants,
        imagePrompt: imagePrompt,
        imagePath: imagePath,
      ),
    );
    return (await greetingById(existing.id))!;
  }

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
