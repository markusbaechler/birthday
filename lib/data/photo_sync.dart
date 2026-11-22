import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../domain/dedupe.dart';
import 'database.dart';

/// Keeps photos in sync with the phone contacts, fully automatic:
/// - people linked to a contact get its current photo (full resolution)
/// - people without a link are linked only on a certain match
///   (same phone number or e-mail), never on a guess
/// Runs only if contacts were imported before, so it never shows a
/// permission prompt on its own.
class PhotoSync {
  PhotoSync(this.db);
  final AppDatabase db;
  var _running = false;

  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      final people = await db.allPeople();
      if (!people.any((p) => p.contactId != null)) return;
      if (!await FlutterContacts.requestPermission(readonly: true)) return;

      // 1. Link people without contact on a certain match.
      final unlinked = people.where((p) => p.contactId == null).toList();
      if (unlinked.isNotEmpty) {
        final contacts = await FlutterContacts.getContacts(withProperties: true);
        for (final p in unlinked) {
          final me = Candidate(
            firstName: p.firstName,
            lastName: p.lastName,
            day: p.birthDay,
            month: p.birthMonth,
            phone: p.phone,
            email: p.email,
          );
          for (final c in contacts) {
            final other = Candidate(
              firstName: c.name.first,
              lastName: c.name.last,
              day: 0,
              month: 0,
              phone: c.phones.firstOrNull?.number,
              email: c.emails.firstOrNull?.address,
            );
            final samePhone = c.phones.any((ph) =>
                normalizePhone(ph.number) != null &&
                normalizePhone(ph.number) == normalizePhone(p.phone));
            if (samePhone ||
                compareCandidates(me, other) == MatchLevel.certain) {
              await db.savePerson(p.copyWith(contactId: Value(c.id)));
              break;
            }
          }
        }
      }

      // 2. Refresh photos of all linked people.
      for (final p in await db.allPeople()) {
        final id = p.contactId;
        if (id == null) continue;
        final contact = await FlutterContacts.getContact(id,
            withProperties: false, withThumbnail: true, withPhoto: true);
        final Uint8List? photo = contact?.photo ?? contact?.thumbnail;
        if (photo == null || photo.isEmpty) continue;
        if (p.photo != null && listEquals(p.photo, photo)) continue;
        await db.savePerson(p.copyWith(photo: Value(photo)));
      }
    } catch (e) {
      debugPrint('Photo sync failed: $e');
    } finally {
      _running = false;
    }
  }
}
