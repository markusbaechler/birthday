import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../domain/birthday.dart';
import '../domain/dedupe.dart';
import 'database.dart';

/// A phone contact with a birthday, ready for the import plan.
class ContactEntry {
  ContactEntry(this.candidate, this.photo);
  final Candidate candidate;
  final Uint8List? photo;
}

class ImportService {
  ImportService(this.db);
  final AppDatabase db;

  /// Asks for read access to the contacts. Returns false if denied.
  Future<bool> requestPermission() =>
      FlutterContacts.requestPermission(readonly: true);

  /// Reads only name, birthday, phone, e-mail and thumbnail.
  Future<List<ContactEntry>> readContactsWithBirthday() async {
    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
      withThumbnail: true,
      withPhoto: true,
    );
    final result = <ContactEntry>[];
    for (final contact in contacts) {
      final birthday = contact.events
          .where((e) => e.label == EventLabel.birthday)
          .firstOrNull;
      if (birthday == null) continue;
      if (!isValidBirthday(birthday.day, birthday.month, birthday.year)) {
        continue;
      }
      final first = contact.name.first.trim();
      final last = contact.name.last.trim();
      final display = contact.displayName.trim();
      result.add(ContactEntry(
        Candidate(
          key: contact.id,
          contactId: contact.id,
          firstName: first.isNotEmpty ? first : display,
          lastName: first.isNotEmpty ? last : '',
          day: birthday.day,
          month: birthday.month,
          year: birthday.year,
          phone: contact.phones.firstOrNull?.number,
          email: contact.emails.firstOrNull?.address,
        ),
        contact.photo ?? contact.thumbnail,
      ));
    }
    return result;
  }

  /// Existing people as candidates; key = database id.
  Future<List<Candidate>> existingCandidates() async {
    final all = await db.allPeople();
    return [for (final p in all) personToCandidate(p)];
  }

  /// Writes the plan. [mergeReviewed] holds the indexes of [ImportPlan.toReview]
  /// the user confirmed as the same person; the others are added as new.
  Future<int> apply(
    ImportPlan plan,
    Map<String, Uint8List?> photos, {
    required Set<int> mergeReviewed,
  }) async {
    var written = 0;
    await db.transaction(() async {
      for (final c in plan.toInsert) {
        await db.addPerson(_companionFor(c, photos[c.contactId]));
        written++;
      }
      for (final m in plan.toMerge) {
        await _fillEmpty(m.existing.key as int, m.incoming, photos);
        written++;
      }
      for (var i = 0; i < plan.toReview.length; i++) {
        final pair = plan.toReview[i];
        if (mergeReviewed.contains(i)) {
          await _fillEmpty(pair.existing.key as int, pair.incoming, photos);
        } else {
          await db.addPerson(
              _companionFor(pair.incoming, photos[pair.incoming.contactId]));
        }
        written++;
      }
    });
    return written;
  }

  PeopleCompanion _companionFor(Candidate c, Uint8List? photo) =>
      PeopleCompanion.insert(
        firstName: c.firstName,
        lastName: Value(c.lastName),
        birthDay: c.day,
        birthMonth: c.month,
        birthYear: Value(c.year),
        phone: Value(c.phone),
        email: Value(c.email),
        contactId: Value(c.contactId),
        photo: Value(photo),
      );

  /// Fills only empty fields. Profiles and notes are never touched.
  Future<void> _fillEmpty(
      int personId, Candidate incoming, Map<String, Uint8List?> photos) async {
    final current = await (db.select(db.people)
          ..where((p) => p.id.equals(personId)))
        .getSingle();
    await db.savePerson(current.copyWith(
      birthYear: Value(current.birthYear ?? incoming.year),
      phone: Value(current.phone ?? incoming.phone),
      email: Value(current.email ?? incoming.email),
      contactId: Value(current.contactId ?? incoming.contactId),
      photo: Value(current.photo ?? photos[incoming.contactId]),
    ));
  }
}

Candidate personToCandidate(Person p) => Candidate(
      key: p.id,
      contactId: p.contactId,
      firstName: p.firstName,
      lastName: p.lastName,
      day: p.birthDay,
      month: p.birthMonth,
      year: p.birthYear,
      phone: p.phone,
      email: p.email,
    );
