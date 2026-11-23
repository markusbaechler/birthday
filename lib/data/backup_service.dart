import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';
import 'share_bridge.dart';

/// Backup as a single JSON file with people, notes, greetings and card
/// images. Written automatically to Download/Geburtstage (survives an
/// uninstall) and shareable by hand, e.g. into Google Drive.
class BackupService {
  BackupService(this.db);
  final AppDatabase db;

  static const formatVersion = 2;

  Future<Map<String, dynamic>> export() async {
    final people = await db.allPeople();
    final notes = await db.allNotes();
    final greetings = await db.select(db.greetings).get();
    final thisYear = DateTime.now().year;
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
      'greetings': [
        for (final g in greetings)
          {
            'id': g.id,
            'personId': g.personId,
            'year': g.year,
            'draft': g.draft,
            'sentText': g.sentText,
            'channel': g.channel,
            'status': g.status,
            'createdAt': g.createdAt.toUtc().toIso8601String(),
            'scheduledAt': g.scheduledAt?.toIso8601String(),
            'variants': g.variants,
            'imagePrompt': g.imagePrompt,
            // Card images of current greetings; old sent ones stay out to
            // keep the file small.
            ..._image(g, thisYear),
          }
      ],
    };
  }

  static Map<String, String> _image(Greeting g, int thisYear) {
    final path = g.imagePath;
    if (path == null) return const {};
    if (g.status == GreetingStatus.sent && g.year < thisYear) return const {};
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() > 12 * 1024 * 1024) return const {};
    return {
      'image': base64Encode(f.readAsBytesSync()),
      'imageExt': CardImages.extensionOf(path),
    };
  }

  // ------------------------------------------------------- Automatic

  static const _folder = 'Download/Geburtstage';

  /// When and where the last automatic backup went, for the settings.
  static Future<({DateTime? at, String? where, String? error})> lastAuto() async {
    final p = await SharedPreferences.getInstance();
    final at = p.getString('backup_at');
    return (
      at: at == null ? null : DateTime.tryParse(at),
      where: p.getString('backup_where'),
      error: p.getString('backup_error'),
    );
  }

  static var _running = false;

  /// Marks the data as changed whenever people, notes or greetings change.
  static void watch(AppDatabase db) {
    Future<void> dirty(Object? _) async =>
        (await SharedPreferences.getInstance()).setBool('backup_dirty', true);
    db.watchPeople().skip(1).listen(dirty);
    db.watchGreetings().skip(1).listen(dirty);
    db.select(db.notes).watch().skip(1).listen(dirty);
  }

  /// Writes a backup when something changed since the last one ([force]:
  /// always). One file per day, the last seven are kept.
  Future<bool> autoBackup({bool force = false}) async {
    if (_running) return false;
    _running = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      final dirty = prefs.getBool('backup_dirty') ?? true;
      if (!force && !dirty && prefs.getString('backup_at') != null) return false;
      final data = await export();
      if ((data['people'] as List).isEmpty) return false;
      final dir = await getTemporaryDirectory();
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final name = 'geburtstage-sicherung-$day.json';
      final file = File('${dir.path}/$name');
      await file.writeAsString(jsonEncode(data), flush: true);
      var where = _folder;
      var ok = await ShareBridge.saveToDownloads(file.path, name, keep: 7);
      if (!ok) {
        // Older Android: the app's own folder on the shared storage.
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          await file.copy('${ext.path}/$name');
          where = ext.path;
          ok = true;
        }
      }
      try {
        await file.delete();
      } catch (_) {}
      if (!ok) throw const FileSystemException('Kein Speicherort verfügbar');
      await prefs.setBool('backup_dirty', false);
      await prefs.setString('backup_at', DateTime.now().toIso8601String());
      await prefs.setString('backup_where', where);
      await prefs.remove('backup_error');
      return true;
    } catch (e) {
      await prefs.setString('backup_error', '$e');
      return false;
    } finally {
      _running = false;
    }
  }

  /// Writes the backup to a file and opens the share sheet.
  Future<void> shareBackup() async {
    final data = await export();
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/geburtstage-sicherung-$stamp.json');
    await file.writeAsString(jsonEncode(data));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: 'Geburtstage: Backup vom $stamp',
    ));
  }

  /// Lets the user pick a backup file. Returns null if cancelled.
  Future<Map<String, dynamic>?> pickBackup() async {
    final file = await FilePicker.pickFile();
    if (file == null) return null;
    final bytes = await file.readAsBytes();
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
    final greetings = (data['greetings'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final restored = <GreetingsCompanion>[];
    for (final g in greetings) {
      String? imagePath;
      if (g['image'] is String) {
        try {
          imagePath = await CardImages.store(
              g['personId'] as int, g['year'] as int, base64Decode(g['image'] as String),
              extension: g['imageExt'] as String? ?? 'jpg');
        } catch (_) {}
      }
      restored.add(GreetingsCompanion(
        id: Value(g['id'] as int),
        personId: Value(g['personId'] as int),
        year: Value(g['year'] as int),
        draft: Value(g['draft'] as String?),
        sentText: Value(g['sentText'] as String?),
        channel: Value(g['channel'] as String? ?? Channels.whatsapp),
        status: Value(g['status'] as String? ?? GreetingStatus.draft),
        createdAt: Value(DateTime.parse(g['createdAt'] as String)),
        scheduledAt: Value(g['scheduledAt'] == null
            ? null
            : DateTime.parse(g['scheduledAt'] as String)),
        variants: Value(g['variants'] as String?),
        imagePrompt: Value(g['imagePrompt'] as String?),
        imagePath: Value(imagePath),
      ));
    }
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
      restored,
    );
    return people.length;
  }
}
