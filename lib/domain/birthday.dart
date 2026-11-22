/// Pure date logic for birthdays. No Flutter imports, fully unit-tested.
library;

/// The next occurrence of a birthday, seen from a given day.
class NextBirthday {
  const NextBirthday({
    required this.date,
    required this.daysUntil,
    required this.turning,
  });

  /// Calendar date of the next birthday (time is always midnight UTC).
  final DateTime date;

  /// 0 = today, 1 = tomorrow, …
  final int daysUntil;

  /// Age reached on that day, or null if the birth year is unknown.
  final int? turning;

  bool get isToday => daysUntil == 0;
}

bool isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

/// Birthday in a given year. People born on 29 February celebrate on
/// 28 February in years without that day.
DateTime occurrenceIn(int year, int month, int day) {
  if (month == 2 && day == 29 && !isLeapYear(year)) {
    return DateTime.utc(year, 2, 28);
  }
  return DateTime.utc(year, month, day);
}

/// Computes the next birthday from [today] (only its calendar date counts).
NextBirthday nextBirthday({
  required int day,
  required int month,
  int? year,
  required DateTime today,
}) {
  // Work in UTC calendar dates so daylight saving never shifts a day.
  final todayDate = DateTime.utc(today.year, today.month, today.day);
  var date = occurrenceIn(todayDate.year, month, day);
  if (date.isBefore(todayDate)) {
    date = occurrenceIn(todayDate.year + 1, month, day);
  }
  final days = date.difference(todayDate).inDays;
  final turning = year == null ? null : date.year - year;
  return NextBirthday(date: date, daysUntil: days, turning: turning);
}

/// Checks a day/month/year combination before it is saved.
bool isValidBirthday(int day, int month, int? year) {
  if (month < 1 || month > 12 || day < 1) return false;
  if (year != null && (year < 1900 || year > 2100)) return false;
  // 2000 is a leap year, so 29 February is accepted when the year is unknown.
  final probeYear = year ?? 2000;
  final maxDay = DateTime.utc(probeYear, month + 1, 0).day;
  return day <= maxDay;
}
