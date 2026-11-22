import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../domain/birthday.dart';
import 'database.dart';

/// The Anthropic API key, encrypted on the device (Android Keystore).
abstract final class Secrets {
  static const _storage = FlutterSecureStorage();
  static const _key = 'anthropic_api_key';

  static Future<String?> apiKey() => _storage.read(key: _key);

  static Future<void> setApiKey(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: value.trim());
    }
  }
}

class GreetingVariant {
  const GreetingVariant(this.title, this.text);
  final String title;
  final String text;

  Map<String, String> toJson() => {'title': title, 'text': text};

  static List<GreetingVariant> listFromJson(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List;
      return [
        for (final v in list)
          GreetingVariant('${v['title'] ?? ''}', '${v['text'] ?? ''}')
      ];
    } catch (_) {
      return const [];
    }
  }

  static String listToJson(List<GreetingVariant> v) =>
      jsonEncode([for (final x in v) x.toJson()]);
}

class AiException implements Exception {
  const AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Writes personal greetings with Claude. Only what is needed leaves the
/// phone: first name, age, relation, tone, language, insiders, notes and
/// last years' greetings. Never phone numbers, e-mail or photos.
class AiService {
  AiService(this.db);
  final AppDatabase db;

  static const _model = 'claude-sonnet-5-5';
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  static const _system = '''
Du schreibst persönliche Geburtstagsgrüsse, die der Absender selbst verschickt (Ich-Form, ohne Unterschrift).
Regeln:
- Nur Fakten aus den Angaben verwenden. Nichts erfinden: keine Erlebnisse, Orte, Pläne oder Eigenschaften, die nicht genannt sind.
- Kein Floskel-Einstieg wie «Alles Gute zum Geburtstag», «Herzlichen Glückwunsch» oder «Happy Birthday» als erster Satz.
- Jede Variante hat eine eigene Idee (z. B. ein Insider, das Alter, eine Notiz), nicht nur andere Wörter.
- Ton und Sprache genau wie angegeben. «Mundart» heisst Schweizerdeutsch in natürlicher Schreibweise.
- Deutsch immer mit ss statt ß.
- Länge passend zum Kanal: WhatsApp und SMS 1 bis 3 Sätze, E-Mail höchstens 5 Sätze.
- Kein Hashtag. Höchstens ein Emoji, und nur wenn der Ton locker oder frech ist.
- Wiederhole keine Formulierung aus den Grüssen früherer Jahre.
Antworte ausschliesslich mit JSON: {"variants":[{"title":"2-3 Wörter zur Idee","text":"…"},{…},{…}]} mit genau 3 Varianten.''';

  /// Three new variants. [instruction] rewrites [baseText] (e.g. «kürzer»).
  Future<List<GreetingVariant>> generate(
    Person p, {
    String? instruction,
    String? baseText,
  }) async {
    final key = await Secrets.apiKey();
    if (key == null) {
      throw const AiException(
          'Kein API-Schlüssel hinterlegt. Unter «Mehr» eintragen.');
    }
    final next = nextBirthday(
        day: p.birthDay, month: p.birthMonth, year: p.birthYear, today: DateTime.now());
    final notes = (await db.allNotes())
        .where((n) =>
            n.personId == p.id &&
            n.createdAt.isAfter(DateTime.now().subtract(const Duration(days: 400))))
        .map((n) => '- ${n.body}')
        .join('\n');
    final earlier = (await db.sentGreetingsFor(p.id))
        .take(3)
        .map((g) => '- ${g.year}: ${g.sentText ?? g.draft ?? ''}')
        .join('\n');

    final facts = StringBuffer()
      ..writeln('Vorname: ${p.nickname?.trim().isNotEmpty == true ? p.nickname!.trim() : p.firstName}')
      ..writeln(next.turning != null ? 'Wird: ${next.turning}' : 'Alter: unbekannt')
      ..writeln('Beziehung: ${p.relation?.trim().isNotEmpty == true ? p.relation : 'nicht angegeben'}')
      ..writeln('Ton: ${p.tone?.trim().isNotEmpty == true ? p.tone : 'herzlich'}')
      ..writeln('Sprache: ${p.language?.trim().isNotEmpty == true ? p.language : 'Deutsch (Schweiz)'}')
      ..writeln('Kanal: ${Channels.label(p.channel)}')
      ..writeln('Insider und Erlebnisse:\n${p.insiders.trim().isEmpty ? '- keine angegeben' : p.insiders.trim()}')
      ..writeln('Notizen der letzten Monate:\n${notes.isEmpty ? '- keine' : notes}')
      ..writeln('Grüsse früherer Jahre:\n${earlier.isEmpty ? '- keine' : earlier}');
    if (instruction != null && baseText != null) {
      facts
        ..writeln()
        ..writeln('Überarbeite diesen Entwurf: «$baseText»')
        ..writeln('Änderung: $instruction. Drei Varianten dieser Überarbeitung.');
    }

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 1200,
              'system': _system,
              'messages': [
                {'role': 'user', 'content': facts.toString()}
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw const AiException('Keine Verbindung. Bitte später nochmals.');
    }
    if (res.statusCode == 401) {
      throw const AiException('Der API-Schlüssel ist ungültig.');
    }
    if (res.statusCode != 200) {
      throw AiException('Die KI antwortet nicht (Fehler ${res.statusCode}).');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final text = (body['content'] as List)
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const AiException('Die Antwort liess sich nicht lesen.');
    }
    final parsed = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    final variants = [
      for (final v in parsed['variants'] as List)
        GreetingVariant('${v['title'] ?? ''}',
            '${v['text'] ?? ''}'.replaceAll('ß', 'ss').trim())
    ].where((v) => v.text.isNotEmpty).toList();
    if (variants.isEmpty) {
      throw const AiException('Die KI hat keinen Text geliefert.');
    }
    return variants;
  }

  /// Quick check for the settings screen.
  static Future<bool> testKey(String key) async {
    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': key.trim(),
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 5,
              'messages': [
                {'role': 'user', 'content': 'Antworte mit OK.'}
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
