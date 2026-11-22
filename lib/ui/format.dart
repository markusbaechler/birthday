import '../data/database.dart';
import '../domain/birthday.dart';

const _weekdaysShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
const _weekdaysLong = [
  'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'
];
const monthNames = [
  'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August',
  'September', 'Oktober', 'November', 'Dezember'
];

/// «Fr 27.11.»
String formatShort(DateTime d) =>
    '${_weekdaysShort[d.weekday - 1]} ${d.day}.${d.month}.';

/// «Freitag, 27. November»
String formatLong(DateTime d) =>
    '${_weekdaysLong[d.weekday - 1]}, ${d.day}. ${monthNames[d.month - 1]}';

/// «SO, 22. NOVEMBER» for the top label.
String formatToday(DateTime d) =>
    '${_weekdaysShort[d.weekday - 1]}, ${d.day}. ${monthNames[d.month - 1]}';

String displayName(Person p) =>
    (p.nickname?.trim().isNotEmpty ?? false) ? p.nickname!.trim() : p.firstName;

String fullName(Person p) => '${p.firstName} ${p.lastName}'.trim();

/// «heute», «morgen», «in 5 Tagen»
String inDays(int days) => switch (days) {
      0 => 'heute',
      1 => 'morgen',
      _ => 'in $days Tagen',
    };

/// A person together with the next birthday, sorted by date.
class Upcoming {
  Upcoming(this.person, this.next);
  final Person person;
  final NextBirthday next;
}

List<Upcoming> upcomingFor(List<Person> people, DateTime today) {
  final list = [
    for (final p in people)
      Upcoming(
        p,
        nextBirthday(
            day: p.birthDay, month: p.birthMonth, year: p.birthYear, today: today),
      )
  ]..sort((a, b) => a.next.daysUntil.compareTo(b.next.daysUntil));
  return list;
}

/// What a hero shows. The big element is the age, or the name when the
/// birth year is unknown; days until the birthday are only ever small.
class HeroText {
  const HeroText(this.lead, this.big, this.caption);
  final String lead;
  final String big;
  final String caption;

  bool get bigIsNumber => int.tryParse(big) != null;
}

HeroText heroTextFor(Upcoming u) {
  final p = u.person;
  final n = u.next;
  final name = displayName(p);
  final when = n.isToday ? 'heute' : inDays(n.daysUntil);
  if (n.turning != null) {
    return HeroText(
      n.isToday ? '$name wird heute' : '$name wird',
      '${n.turning}',
      n.isToday ? fullName(p) : '$when · ${formatLong(n.date)}',
    );
  }
  return HeroText(
    n.isToday ? 'Heute hat Geburtstag' : 'Geburtstag $when',
    name,
    n.isToday ? fullName(p) : formatLong(n.date),
  );
}
