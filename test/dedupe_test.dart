import 'package:flutter_test/flutter_test.dart';
import 'package:geburtstage/domain/dedupe.dart';

Candidate c(String first, String last,
        {int day = 27,
        int month = 11,
        int? year,
        String? phone,
        String? email,
        String? contactId}) =>
    Candidate(
      firstName: first,
      lastName: last,
      day: day,
      month: month,
      year: year,
      phone: phone,
      email: email,
      contactId: contactId,
    );

void main() {
  group('normalizeName', () {
    test('folds umlauts, case and word order', () {
      expect(normalizeName('Jürg Müller'), normalizeName('mueller juerg'));
      expect(normalizeName('  Anna-Lena  Rossi '), 'anna lena rossi');
      expect(normalizeName('Zoë'), 'zoe');
    });
  });

  group('normalizePhone', () {
    test('reads Swiss numbers in all common spellings', () {
      expect(normalizePhone('079 123 45 67'), '+41791234567');
      expect(normalizePhone('+41 79 123 45 67'), '+41791234567');
      expect(normalizePhone('0041791234567'), '+41791234567');
      expect(normalizePhone('+49 151 2345678'), '+491512345678');
    });

    test('rejects junk', () {
      expect(normalizePhone(null), isNull);
      expect(normalizePhone(''), isNull);
      expect(normalizePhone('12345'), isNull);
    });
  });

  group('jaroWinkler', () {
    test('known values', () {
      expect(jaroWinkler('martha', 'marhta'), closeTo(0.961, 0.001));
      expect(jaroWinkler('abc', 'abc'), 1.0);
      expect(jaroWinkler('abc', ''), 0.0);
    });
  });

  group('compareCandidates', () {
    test('same phone in different spelling is certain', () {
      expect(
        compareCandidates(c('Marco', 'Keller', phone: '079 123 45 67'),
            c('M.', 'K.', day: 1, month: 1, phone: '+41791234567')),
        MatchLevel.certain,
      );
    });

    test('same e-mail is certain', () {
      expect(
        compareCandidates(c('Lea', 'Brunner', email: 'Lea@Example.ch'),
            c('Lea', 'B', email: 'lea@example.ch ')),
        MatchLevel.certain,
      );
    });

    test('similar name and same birthday is likely', () {
      expect(compareCandidates(c('Marco', 'Keller'), c('Keller', 'Marco')),
          MatchLevel.likely);
      expect(compareCandidates(c('Jürg', 'Müller'), c('Juerg', 'Mueller')),
          MatchLevel.likely);
    });

    test('same name, different birthday is not a match', () {
      expect(compareCandidates(c('Marco', 'Keller'), c('Marco', 'Keller', day: 28)),
          MatchLevel.none);
    });

    test('conflicting birth years are not a match', () {
      expect(
          compareCandidates(
              c('Marco', 'Keller', year: 1981), c('Marco', 'Keller', year: 1990)),
          MatchLevel.none);
    });

    test('different people with same birthday are not a match', () {
      expect(compareCandidates(c('Anna', 'Meier'), c('Sofia', 'Rossi')),
          MatchLevel.none);
    });
  });

  group('buildImportPlan', () {
    test('sorts into insert, merge, review and skips source duplicates', () {
      final existing = [
        c('Marco', 'Keller', phone: '079 111 11 11'),
        c('Lea', 'Brunner', day: 22),
      ];
      final incoming = [
        c('Marco K', '', phone: '+41791111111'), // certain → merge
        c('Lea', 'Bruner', day: 22), // likely → review
        c('Sofia', 'Rossi', day: 3, month: 12, phone: '078 222 22 22'), // new
        c('Sofia R', '', day: 3, month: 12, phone: '0782222222'), // dup in source
      ];
      final plan = buildImportPlan(incoming: incoming, existing: existing);
      expect(plan.toMerge, hasLength(1));
      expect(plan.toReview, hasLength(1));
      expect(plan.toInsert, hasLength(1));
      expect(plan.toInsert.single.firstName, 'Sofia');
      expect(plan.skippedDuplicatesInSource, 1);
      expect(plan.total, 3);
    });

    test('empty database imports everything', () {
      final plan = buildImportPlan(
          incoming: [c('A', 'B'), c('C', 'D', day: 1)], existing: const []);
      expect(plan.toInsert, hasLength(2));
      expect(plan.toReview, isEmpty);
    });
  });
}
