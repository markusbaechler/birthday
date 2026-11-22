import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database.dart';

/// Backup as a single JSON file. Phase 1: shared via the Android share sheet
/// (e.g. into Google Drive). An automatic Drive backup follows later.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  static const formatVersion = 1;

  Future<Map<String, dynamic>> export() async {
    final people = await db.allPeople();
    final notes = await db.allNotes();
    return {
      'format': 'geburtstage-backup',
      'version': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'people': [
        for (final p in people)
          {
            'id': p.id,
            'firstName': p.firstName,
            'lastName': p.lastName,
            'nickname': p.nickname,
            'birthDay': p.birthDay,
            'birthMonth': p.birthMonth,
            'birthYear': p.birthYear,
            'phone': p.phone,
            'email': p.email,
            'photo': p.photo == null ? null : base64Encode(p.photo!),
            'contactId': p.contactId,
            'channel': p.channel,
            'relation': p.relation,
            'tone': p.tone,
            'language': p.language,
            'insiders': p.insiders,
            'colorIndex': p.colorIndex,
            'createdAt': p.createdAt.toUtc().toIso8601String(),
          }
      ],
      'notes': [
        for (final n in notes)
          {
            'id': n.id,
            'personId': n.personId,
            'body': n.body,
            'createdAt': n.createdAt.toUtc().toIso8601String(),
          }
      ],
    };
  }

  /// Writes the backup to a file and opens the share sheet.
  Future<void> shareBackup() async {
    final data = await export();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/geburtstage-backup-$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
        subject: 'Geburtstage: Backup vom $stamp');
  }

  /// Lets the user pick a backup file. Returns null if cancelled.
  Future<Map<String, dynamic>?> pickBackup() async {
    final result = await FilePicker.platform.pickFiles(
      // FileType.any: some Android pickers do not know a MIME type for .json.
      type: FileType.any,
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'geburtstage-backup') {
      throw const FormatException('Das ist keine Geburtstage-Sicherung.');
    }
    return decoded;
  }

  /// Replaces all data with the backup content.
  Future<int> restore(Map<String, dynamic> data) async {
    final people = (data['people'] as List).cast<Map<String, dynamic>>();
    final notes = (data['notes'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    await db.replaceAll(
      [
        for (final p in people)
          PeopleCompanion.insert(
            id: Value(p['id'] as int),
            firstName: p['firstName'] as String,
            lastName: Value(p['lastName'] as String? ?? ''),
            nickname: Value(p['nickname'] as String?),
            birthDay: p['birthDay'] as int,
            birthMonth: p['birthMonth'] as int,
            birthYear: Value(p['birthYear'] as int?),
            phone: Value(p['phone'] as String?),
            email: Value(p['email'] as String?),
            photo: Value(p['photo'] == null
                ? null
                : base64Decode(p['photo'] as String)),
            contactId: Value(p['contactId'] as String?),
            channel: Value(p['channel'] as String? ?? Channels.whatsapp),
            relation: Value(p['relation'] as String?),
            tone: Value(p['tone'] as String?),
            language: Value(p['language'] as String?),
            insiders: Value(p['insiders'] as String? ?? ''),
            colorIndex: Value(p['colorIndex'] as int? ?? 0),
            createdAt: Value(DateTime.parse(p['createdAt'] as String)),
          )
      ],
      [
        for (final n in notes)
          NotesCompanion.insert(
            id: Value(n['id'] as int),
            personId: n['personId'] as int,
            body: n['body'] as String,
            createdAt: Value(DateTime.parse(n['createdAt'] as String)),
          )
      ],
    );
    return people.length;
  }
}
