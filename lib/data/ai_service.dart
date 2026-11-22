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

  static const _imageSystem = """
Du schreibst einen Bildprompt für ChatGPT (Bildgenerierung). Daraus entsteht eine persönliche Geburtstagskarte, die zusammen mit einem Gruss per WhatsApp verschickt wird.
Regeln:
- Schreibe den Prompt auf Deutsch, als direkte Anweisung an ChatGPT, 90 bis 160 Wörter, ein einziger Absatz.
- Hochformat 4:5. Eine klare Bildidee statt vieler Einzelteile. Ein konkreter Stil (z. B. Risographie, Aquarell, Scherenschnitt, 3D-Knete, Linolschnitt, Fotografie), passend zu Ton und Beziehung.
- Motive nur aus den Angaben (Insider, Notizen, Beziehung, Alter). Nichts erfinden. Fehlen Angaben: ein schönes, eigenständiges Motiv ohne persönliche Details.
- Keine realen Personen nachbilden, keine Gesichter von echten Menschen, keine Marken und Logos.
- Auf der Karte steht genau ein kurzer Schriftzug mit dem Vornamen, z. B. «Alles Gute, Silvia» oder in Mundart, wenn die Sprache Mundart ist. Schreibe den Schriftzug wörtlich in Anführungszeichen und verlange korrekte Rechtschreibung. Sonst kein Text im Bild.
- Deutsch immer mit ss statt ß.
Antworte nur mit dem Prompt, ohne Einleitung und ohne Anführungszeichen drumherum.""";

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
  Future<String> imagePrompt(Person p, {String? greeting, String? wish}) async {
    final facts = StringBuffer(await _facts(p));
    if (greeting != null && greeting.trim().isNotEmpty) {
      facts.writeln('Der Gruss, der mit der Karte geht (nur für die Stimmung): «${greeting.trim()}»');
    }
    if (wish != null && wish.trim().isNotEmpty) {
      facts.writeln('Wunsch für das Bild: ${wish.trim()}');
    }
    final text = await _call(_imageSystem, facts.toString(), 700);
    final prompt = text.trim().replaceAll('ß', 'ss');
    if (prompt.isEmpty) throw const AiException('Die KI hat keinen Prompt geliefert.');
    return prompt;
  }

  /// A prompt without AI, from the profile alone (no API key needed).
  static String fallbackImagePrompt(Person p) {
    final name = p.nickname?.trim().isNotEmpty == true ? p.nickname!.trim() : p.firstName;
    final next = nextBirthday(
        day: p.birthDay, month: p.birthMonth, year: p.birthYear, today: DateTime.now());
    final insiders = p.insiders.trim().replaceAll('\n', ', ');
    return [
      'Gestalte eine Geburtstagskarte im Hochformat 4:5 als moderne Illustration im Risographie-Stil, mit wenigen kräftigen Farben auf warmem Papierton und feiner Körnung.',
      if (next.turning != null) 'Anlass: ${next.turning}. Geburtstag; die Zahl darf als grafisches Element vorkommen.',
      if (insiders.isNotEmpty) 'Baue diese persönlichen Motive ein: $insiders.',
      'Viel Luft, eine klare Bildidee, keine realen Personen, keine Logos.',
      'Einziger Text im Bild, korrekt geschrieben: «Alles Gute, $name».',
    ].join(' ');
  }

  Future<String> _call(String system, String user, int maxTokens) async {
    final key = await Secrets.apiKey();
    if (key == null) {
      throw const AiException(
          'Kein API-Schlüssel hinterlegt. Unter «Mehr» eintragen.');
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
              'max_tokens': maxTokens,
              'system': system,
              'messages': [
                {'role': 'user', 'content': user}
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
    return (body['content'] as List)
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join();
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
