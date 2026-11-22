/// Duplicate detection for the contact import. Pure Dart, unit-tested.
library;

import 'dart:math' as math;

/// The fields of a person that matter for matching.
class Candidate {
  const Candidate({
    this.key,
    this.contactId,
    required this.firstName,
    this.lastName = '',
    required this.day,
    required this.month,
    this.year,
    this.phone,
    this.email,
  });

  /// Caller-defined reference (e.g. database id or contact id).
  final Object? key;
  final String? contactId;
  final String firstName;
  final String lastName;
  final int day;
  final int month;
  final int? year;
  final String? phone;
  final String? email;

  String get fullName => '$firstName $lastName'.trim();
}

enum MatchLevel { none, likely, certain }

const _foldMap = {
  'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss',
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u',
  'ç': 'c', 'ñ': 'n', 'ÿ': 'y',
};

/// Lower case, umlauts folded (ä → ae), punctuation dropped, words sorted.
/// Word order is ignored so "Keller Marco" equals "Marco Keller".
String normalizeName(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final folded = _foldMap[ch];
    if (folded != null) {
      buffer.write(folded);
    } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
      buffer.write(ch);
    } else {
      buffer.write(' ');
    }
  }
  final words = buffer
      .toString()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList()
    ..sort();
  return words.join(' ');
}

/// Normalises a phone number to E.164. Numbers without a country code are
/// read as Swiss (+41). Returns null for anything shorter than 7 digits.
String? normalizePhone(String? raw, {String defaultCountryCode = '41'}) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 7) return null;
  if (hasPlus) return '+$digits';
  if (digits.startsWith('00')) return '+${digits.substring(2)}';
  if (digits.startsWith('0')) return '+$defaultCountryCode${digits.substring(1)}';
  return '+$digits';
}

String? normalizeEmail(String? raw) {
  if (raw == null) return null;
  final e = raw.trim().toLowerCase();
  return e.contains('@') ? e : null;
}

/// Jaro-Winkler similarity between 0 (different) and 1 (identical).
double jaroWinkler(String a, String b) {
  if (a == b) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  final matchDistance = math.max(0, math.max(a.length, b.length) ~/ 2 - 1);
  final aMatches = List<bool>.filled(a.length, false);
  final bMatches = List<bool>.filled(b.length, false);
  var matches = 0;
  for (var i = 0; i < a.length; i++) {
    final start = math.max(0, i - matchDistance);
    final end = math.min(i + matchDistance + 1, b.length);
    for (var j = start; j < end; j++) {
      if (bMatches[j] || a[i] != b[j]) continue;
      aMatches[i] = true;
      bMatches[j] = true;
      matches++;
      break;
    }
  }
  if (matches == 0) return 0.0;
  var transpositions = 0;
  var k = 0;
  for (var i = 0; i < a.length; i++) {
    if (!aMatches[i]) continue;
    while (!bMatches[k]) {
      k++;
    }
    if (a[i] != b[k]) transpositions++;
    k++;
  }
  final m = matches.toDouble();
  final jaro =
      (m / a.length + m / b.length + (m - transpositions / 2) / m) / 3.0;
  var prefix = 0;
  for (var i = 0; i < math.min(4, math.min(a.length, b.length)); i++) {
    if (a[i] != b[i]) break;
    prefix++;
  }
  return jaro + prefix * 0.1 * (1 - jaro);
}

/// Threshold for "likely the same person" on the normalised full name.
const likelyNameThreshold = 0.9;

/// Compares two people.
/// certain: same contact id, same phone or same e-mail.
/// likely:  similar name (≥ 0.9) and same birthday (day and month).
MatchLevel compareCandidates(Candidate a, Candidate b) {
  if (a.contactId != null && a.contactId == b.contactId) {
    return MatchLevel.certain;
  }
  final pa = normalizePhone(a.phone);
  final pb = normalizePhone(b.phone);
  if (pa != null && pa == pb) return MatchLevel.certain;
  final ea = normalizeEmail(a.email);
  final eb = normalizeEmail(b.email);
  if (ea != null && ea == eb) return MatchLevel.certain;

  final sameBirthday = a.day == b.day && a.month == b.month;
  final yearsConflict = a.year != null && b.year != null && a.year != b.year;
  if (!sameBirthday || yearsConflict) return MatchLevel.none;
  final similarity =
      jaroWinkler(normalizeName(a.fullName), normalizeName(b.fullName));
  return similarity >= likelyNameThreshold
      ? MatchLevel.likely
      : MatchLevel.none;
}

/// A pair the user has to confirm.
class LikelyPair {
  const LikelyPair(this.incoming, this.existing);
  final Candidate incoming;
  final Candidate existing;
}

/// A certain match: [incoming] fills empty fields of [existing].
class CertainMerge {
  const CertainMerge(this.incoming, this.existing);
  final Candidate incoming;
  final Candidate existing;
}

class ImportPlan {
  const ImportPlan({
    required this.toInsert,
    required this.toMerge,
    required this.toReview,
    required this.skippedDuplicatesInSource,
  });

  /// New people, no match at all.
  final List<Candidate> toInsert;

  /// Certain matches with existing people: fill empty fields only.
  final List<CertainMerge> toMerge;

  /// Likely matches: the user decides.
  final List<LikelyPair> toReview;

  /// Entries that appeared twice in the source (e.g. same phone twice).
  final int skippedDuplicatesInSource;

  int get total => toInsert.length + toMerge.length + toReview.length;
}

/// Builds the import plan. Never deletes or overwrites anything.
ImportPlan buildImportPlan({
  required List<Candidate> incoming,
  required List<Candidate> existing,
}) {
  // 1. Collapse certain duplicates inside the source itself.
  final unique = <Candidate>[];
  var skipped = 0;
  for (final c in incoming) {
    final dup = unique.any((u) => compareCandidates(u, c) == MatchLevel.certain);
    if (dup) {
      skipped++;
    } else {
      unique.add(c);
    }
  }

  // 2. Compare with existing people: certain beats likely.
  final toInsert = <Candidate>[];
  final toMerge = <CertainMerge>[];
  final toReview = <LikelyPair>[];
  for (final c in unique) {
    Candidate? likely;
    Candidate? certain;
    for (final e in existing) {
      final level = compareCandidates(c, e);
      if (level == MatchLevel.certain) {
        certain = e;
        break;
      }
      if (level == MatchLevel.likely) likely ??= e;
    }
    if (certain != null) {
      toMerge.add(CertainMerge(c, certain));
    } else if (likely != null) {
      toReview.add(LikelyPair(c, likely));
    } else {
      toInsert.add(c);
    }
  }
  return ImportPlan(
    toInsert: toInsert,
    toMerge: toMerge,
    toReview: toReview,
    skippedDuplicatesInSource: skipped,
  );
}
