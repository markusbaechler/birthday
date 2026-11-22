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

  /// Tried in order; the next one only when a model is not available.
  static const _models = ['claude-sonnet-5-5', 'claude-sonnet-4-5'];
  static var _model = _models.first;
  static var _bearer = true;
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

  static const _imageSystem = """
Du bist Art Director und schreibst einen Bildprompt für eine Bild-KI. Daraus entsteht eine Geburtstagskarte, die als Bild per WhatsApp verschickt wird. Sie soll sofort als persönlich erkennbar sein und auf Handygrösse in einer Sekunde wirken.

Vorgehen (nur im Kopf, nicht ausgeben):
1. Sammle aus den Angaben alles Sichtbare: Hobbys, Orte, Gegenstände, Eigenheiten, Running Gags, das Alter. Übersetze Eigenschaften in Bilder (aus «immer zu spät» wird etwa eine Uhr, ein davonfahrender Zug, ein schmelzendes Zifferblatt).
2. Entwickle drei verschiedene Bildideen mit je einer kleinen Pointe aus diesen Angaben. Wähle die originellste, die trotzdem auf einen Blick verständlich ist.
3. Fehlen persönliche Angaben, wähle eine starke, elegante Idee rund ums Feiern und das Alter und erfinde keine Details über die Person.

Ausgabe: der Prompt auf Deutsch (ss statt ß), genau diese sieben Zeilen, jede beginnt mit ihrem Label:
Format: Hochformat 4:5, randlos, Geburtstagskarte.
Bildidee: ein Satz, was man sieht und worin die Pointe liegt.
Szene: 2 bis 4 Sätze mit Hauptmotiv, Nebenmotiven, Anordnung von vorne nach hinten, Blickführung, Perspektive. Konkret und gegenständlich, keine Adjektiv-Ketten.
Stil: Medium und Technik präzise benannt (z. B. «Risographie-Druck in drei Farben mit leichtem Passerversatz und Papierkorn»).
Farben und Licht: 3 bis 5 benannte Farben und die Lichtstimmung.
Schrift: der Schriftzug wörtlich in «», höchstens fünf Wörter mit dem Vornamen (in Mundart, wenn die Sprache Mundart ist), dazu Schriftcharakter, Grösse und Position; ausdrücklich fehlerfrei geschrieben und gut lesbar; kein weiterer Text im Bild.
Vermeiden: reale Personen und Gesichter echter Menschen, Marken, Logos, Wasserzeichen, Rahmen, zusätzlicher Text, generische Ballons und Konfetti (ausser sie sind Teil der Idee).

Regeln: Motive nur aus den Angaben (Insider, Notizen, Beziehung, Alter, Gruss). Keine Nachnamen. Ist ein Stil vorgegeben, halte dich daran. Antworte nur mit den sieben Zeilen.""";

  /// What the AI may know about [p]: no phone, e-mail, last name or photo.
  Future<String> _facts(Person p) async {
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
    return (StringBuffer()
          ..writeln('Vorname: ${p.nickname?.trim().isNotEmpty == true ? p.nickname!.trim() : p.firstName}')
          ..writeln(next.turning != null ? 'Wird: ${next.turning}' : 'Alter: unbekannt')
          ..writeln('Beziehung: ${p.relation?.trim().isNotEmpty == true ? p.relation : 'nicht angegeben'}')
          ..writeln('Ton: ${p.tone?.trim().isNotEmpty == true ? p.tone : 'herzlich'}')
          ..writeln('Sprache: ${p.language?.trim().isNotEmpty == true ? p.language : 'Deutsch (Schweiz)'}')
          ..writeln('Kanal: ${Channels.label(p.channel)}')
          ..writeln('Insider und Erlebnisse:\n${p.insiders.trim().isEmpty ? '- keine angegeben' : p.insiders.trim()}')
          ..writeln('Notizen der letzten Monate:\n${notes.isEmpty ? '- keine' : notes}')
          ..writeln('Grüsse früherer Jahre:\n${earlier.isEmpty ? '- keine' : earlier}'))
        .toString();
  }

  /// Three new variants. With [baseText], [instruction] rewrites it
  /// (e.g. «kürzer»); without, [instruction] is a wish for new drafts.
  Future<List<GreetingVariant>> generate(
    Person p, {
    String? instruction,
    String? baseText,
  }) async {
    final facts = StringBuffer(await _facts(p));
    final hasBase = baseText != null && baseText.trim().isNotEmpty;
    if (instruction != null && hasBase) {
      facts
        ..writeln()
        ..writeln('Überarbeite diesen Entwurf: «${baseText.trim()}»')
        ..writeln('Änderung: $instruction. Drei Varianten dieser Überarbeitung.');
    } else if (instruction != null) {
      facts
        ..writeln()
        ..writeln('Wunsch für alle drei Varianten: $instruction');
    }
    final text = await _call(_system, facts.toString(), 1200);
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

  /// A prompt for ChatGPT to design a birthday card for [p]. [greeting] sets
  /// the mood; it is not written onto the card.
  Future<String> imagePrompt(Person p,
      {String? greeting, String? wish, String? style, String? ai}) async {
    final facts = StringBuffer(await _facts(p));
    if (ai != null) facts.writeln('Bild-KI: $ai');
    if (style != null) facts.writeln('Stilvorgabe: $style');
    if (greeting != null && greeting.trim().isNotEmpty) {
      facts.writeln('Der Gruss, der mit der Karte geht (nur für die Stimmung): «${greeting.trim()}»');
    }
    if (wish != null && wish.trim().isNotEmpty) {
      facts.writeln('Wunsch für das Bild: ${wish.trim()}');
    }
    final text = await _call(_imageSystem, facts.toString(), 1500);
    final prompt = text.trim().replaceAll('ß', 'ss');
    if (prompt.isEmpty) throw const AiException('Die KI hat keinen Prompt geliefert.');
    return prompt;
  }

  /// A prompt without AI, from the profile alone (no API key needed).
  static String fallbackImagePrompt(Person p, {String? style}) {
    final name = p.nickname?.trim().isNotEmpty == true ? p.nickname!.trim() : p.firstName;
    final next = nextBirthday(
        day: p.birthDay, month: p.birthMonth, year: p.birthYear, today: DateTime.now());
    final insiders = p.insiders
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final age = next.turning;
    return [
      'Format: Hochformat 4:5, randlos, Geburtstagskarte.',
      insiders.isNotEmpty
          ? 'Bildidee: eine kleine, augenzwinkernde Szene rund um «${insiders.first}»${age != null ? ', in der die Zahl $age versteckt als Teil der Szene auftaucht' : ''}.'
          : 'Bildidee: ${age != null ? 'die Zahl $age als grosse, festliche Skulptur, um die herum gefeiert wird' : 'ein einzelnes, festliches Objekt als Mittelpunkt einer Feier'}.',
      'Szene: Hauptmotiv gross im unteren Drittel, darüber ruhiger Raum für die Schrift. ${insiders.length > 1 ? 'Kleine Details im Hintergrund: ${insiders.skip(1).join(', ')}.' : 'Wenige, sorgfältig gesetzte Details.'}',
      'Stil: ${style ?? 'Risographie-Druck in drei Farben mit leichtem Passerversatz und Papierkorn'}.',
      'Farben und Licht: warmes Papierweiss, Koralle, tiefes Petrol, ein Akzent in Gold; weiches, gleichmässiges Licht.',
      'Schrift: «Alles Gute, $name» oben mittig in einer kräftigen, freundlichen Grotesk, fehlerfrei geschrieben und gut lesbar; kein weiterer Text.',
      'Vermeiden: reale Personen und Gesichter, Marken, Logos, Wasserzeichen, Rahmen, zusätzlicher Text, generische Ballons und Konfetti.',
    ].join('\n');
  }

  Future<String> _call(String system, String user, int maxTokens) async {
    final key = await Secrets.apiKey();
    if (key == null) {
      throw const AiException(
          'Kein API-Schlüssel hinterlegt. Unter «Mehr» eintragen.');
    }
    final res = await _post(key, {
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': user}
      ],
    });
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (body['content'] as List)
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join();
  }

  /// Sends a request; on «model not found» tries the next model. Throws an
  /// [AiException] with the reason in plain words.
  static Future<http.Response> _post(String key, Map<String, Object?> body,
      {Duration timeout = const Duration(seconds: 60)}) async {
    for (final model in [_model, ..._models.where((m) => m != _model)]) {
      http.Response? res;
      // Newer keys (sk-ant-usr-…) are documented with «Authorization:
      // Bearer», older ones with «x-api-key». Try the remembered one first.
      for (final bearer in [_bearer, !_bearer]) {
        try {
          res = await http
              .post(
                Uri.parse(_endpoint),
                headers: {
                  if (bearer) 'authorization': 'Bearer ${key.trim()}'
                  else 'x-api-key': key.trim(),
                  'anthropic-version': '2023-06-01',
                  'content-type': 'application/json',
                },
                body: jsonEncode({'model': model, ...body}),
              )
              .timeout(timeout);
        } catch (e) {
          throw AiException('Keine Verbindung zur KI ($e).');
        }
        if (res.statusCode != 401) {
          _bearer = bearer;
          break;
        }
      }
      if (res!.statusCode == 200) {
        _model = model;
        return res;
      }
      final reason = _reason(res);
      if (res.statusCode == 404 && reason.toLowerCase().contains('model')) {
        continue;
      }
      throw AiException(_explain(res.statusCode, reason));
    }
    throw const AiException('Kein passendes KI-Modell verfügbar.');
  }

  static String _reason(http.Response res) {
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return '${(j['error'] as Map?)?['message'] ?? ''}';
    } catch (_) {
      return '';
    }
  }

  static String _explain(int status, String reason) {
    final r = reason.toLowerCase();
    if (status == 401) return 'Der Schlüssel wird nicht akzeptiert (401): ${reason.isEmpty ? 'ungültig' : reason}. Neu kopieren, ohne Leerzeichen.';
    if (status == 403) return 'Der Schlüssel hat keine Berechtigung (403): $reason';
    if (r.contains('credit') || r.contains('billing')) {
      return 'Kein Guthaben in der Console. Unter Billing Guthaben laden, dann klappt es.';
    }
    if (status == 429) return 'Zu viele Anfragen oder Limit erreicht (429): $reason';
    if (status == 529 || status >= 500) return 'Die KI ist gerade überlastet ($status). Gleich nochmals.';
    return 'Fehler $status: ${reason.isEmpty ? 'unbekannt' : reason}';
  }

  /// Checks [key]. Null when it works, otherwise the reason.
  /// [usable]: the key itself is valid (e.g. only credit is missing).
  static Future<({String? error, bool usable})> testKey(String key) async {
    try {
      await _post(key.trim(), {
        'max_tokens': 5,
        'messages': [
          {'role': 'user', 'content': 'Antworte mit OK.'}
        ],
      }, timeout: const Duration(seconds: 30));
      return (error: null, usable: true);
    } on AiException catch (e) {
      final m = e.message;
      final usable = !m.contains('(401)') && !m.contains('(403)') &&
          !m.startsWith('Keine Verbindung');
      return (error: m, usable: usable);
    }
  }
}
