import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';

/// How the sender writes: a note and examples they gave, plus what the app
/// learns from greetings they wrote or changed before sending.
class StyleProfile {
  const StyleProfile({
    this.note = '',
    this.ownExamples = '',
    this.learned = const [],
    this.edits = const [],
  });

  /// «So schreibe ich», in the sender's words.
  final String note;

  /// Greetings the sender pasted as examples.
  final String ownExamples;

  /// Sent greetings that are not a plain AI variant.
  final List<String> learned;

  /// (AI draft, what the sender made of it).
  final List<(String, String)> edits;

  bool get isEmpty =>
      note.trim().isEmpty && ownExamples.trim().isEmpty && learned.isEmpty;

  static Future<({String note, String examples})> readOwn() async {
    final p = await SharedPreferences.getInstance();
    return (
      note: p.getString('style_note') ?? '',
      examples: p.getString('style_examples') ?? ''
    );
  }

  static Future<void> writeOwn(String note, String examples) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('style_note', note.trim());
    await p.setString('style_examples', examples.trim());
  }

  static Future<StyleProfile> load(AppDatabase db) async {
    final own = await readOwn();
    final sent = (await db.select(db.greetings).get())
        .where((g) => g.status == GreetingStatus.sent)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final l = learn(sent);
    return StyleProfile(
        note: own.note,
        ownExamples: own.examples,
        learned: l.examples,
        edits: l.edits);
  }

  /// Picks what teaches the sender's voice from [sent] (newest first):
  /// texts they wrote or changed. Texts sent exactly as the AI wrote them
  /// are left out, otherwise the AI would only learn from itself.
  static ({List<String> examples, List<(String, String)> edits}) learn(
      List<Greeting> sent,
      {int maxExamples = 6, int maxEdits = 3}) {
    final examples = <String>[];
    final edits = <(String, String)>[];
    for (final g in sent) {
      final text = (g.sentText ?? '').trim();
      if (text.length < 12) continue;
      final variants = _variantTexts(g.variants);
      if (variants.any((v) => _norm(v) == _norm(text))) continue;
      if (examples.length < maxExamples) examples.add(_cut(text));
      // Closest AI variant: if it is clearly the base, show the change.
      String? base;
      var best = 0.0;
      for (final v in variants) {
        final o = _overlap(v, text);
        if (o > best) {
          best = o;
          base = v;
        }
      }
      if (base != null && best >= 0.45 && edits.length < maxEdits) {
        edits.add((_cut(base), _cut(text)));
      }
    }
    return (examples: examples, edits: edits);
  }

  /// The block that goes to the AI with every greeting request.
  String toPrompt() {
    if (isEmpty) return '';
    final b = StringBuffer()
      ..writeln()
      ..writeln('So schreibt der Absender (Stil übernehmen, Inhalte nicht):');
    if (note.trim().isNotEmpty) b.writeln('Eigene Beschreibung: ${note.trim()}');
    if (ownExamples.trim().isNotEmpty) {
      b.writeln('Eigene Beispiele:\n${_cut(ownExamples.trim(), 900)}');
    }
    if (learned.isNotEmpty) {
      b.writeln('Zuletzt selbst geschriebene oder angepasste Grüsse:');
      for (final e in learned) {
        b.writeln('- $e');
      }
    }
    if (edits.isNotEmpty) {
      b.writeln('So hat der Absender KI-Entwürfe geändert (Entwurf → gesendet):');
      for (final (from, to) in edits) {
        b.writeln('- «$from» → «$to»');
      }
    }
    return b.toString();
  }

  static List<String> _variantTexts(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final v in jsonDecode(json) as List) '${(v as Map)['text'] ?? ''}'
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _cut(String s, [int max = 320]) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max)}…';
  }

  /// Share of the words of the shorter text that also occur in the other.
  static double _overlap(String a, String b) {
    Set<String> words(String s) => _norm(s)
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.length > 2)
        .toSet();
    final wa = words(a), wb = words(b);
    if (wa.isEmpty || wb.isEmpty) return 0;
    final small = wa.length <= wb.length ? wa : wb;
    final large = identical(small, wa) ? wb : wa;
    return small.where(large.contains).length / small.length;
  }
}
