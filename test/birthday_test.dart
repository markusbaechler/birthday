import 'package:flutter_test/flutter_test.dart';
import 'package:geburtstage/domain/birthday.dart';

void main() {
  group('nextBirthday', () {
    test('today counts as 0 days', () {
      final n = nextBirthday(
          day: 22, month: 11, year: 1996, today: DateTime(2026, 11, 22, 23, 59));
      expect(n.daysUntil, 0);
      expect(n.isToday, isTrue);
      expect(n.turning, 30);
    });

    test('later this year', () {
      final n = nextBirthday(day: 27, month: 11, year: 1981, today: DateTime(2026, 11, 22));
      expect(n.daysUntil, 5);
      expect(n.turning, 45);
    });

    test('already passed rolls to next year', () {
      final n = nextBirthday(day: 1, month: 1, year: 2000, today: DateTime(2026, 11, 22));
      expect(n.date, DateTime.utc(2027, 1, 1));
      expect(n.daysUntil, 40);
      expect(n.turning, 27);
    });

    test('unknown year gives no age', () {
      final n = nextBirthday(day: 3, month: 12, today: DateTime(2026, 11, 22));
      expect(n.turning, isNull);
      expect(n.daysUntil, 11);
    });

    test('29 February falls on 28 February in common years', () {
      final n = nextBirthday(day: 29, month: 2, year: 2000, today: DateTime(2026, 11, 22));
      expect(n.date, DateTime.utc(2027, 2, 28));
      final leap = nextBirthday(day: 29, month: 2, year: 2000, today: DateTime(2027, 11, 22));
      expect(leap.date, DateTime.utc(2028, 2, 29));
    });

    test('daylight saving change does not shift the count', () {
      // Swiss clocks change on 29 March 2026.
      final n = nextBirthday(day: 1, month: 4, today: DateTime(2026, 3, 25));
      expect(n.daysUntil, 7);
    });
  });

  group('isValidBirthday', () {
    test('accepts real dates and 29 February without year', () {
      expect(isValidBirthday(31, 1, 1990), isTrue);
      expect(isValidBirthday(29, 2, null), isTrue);
      expect(isValidBirthday(29, 2, 2024), isTrue);
    });

    test('rejects impossible dates', () {
      expect(isValidBirthday(29, 2, 2023), isFalse);
      expect(isValidBirthday(31, 4, null), isFalse);
      expect(isValidBirthday(0, 5, null), isFalse);
      expect(isValidBirthday(10, 13, null), isFalse);
      expect(isValidBirthday(10, 5, 1800), isFalse);
    });
  });
}
