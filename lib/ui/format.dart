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

/// What a hero shows: the first name is the big element; when and age are
/// small lines around it.
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
  final when = switch (n.daysUntil) {
    0 => 'Heute',
    1 => 'Morgen',
    _ => 'In ${n.daysUntil} Tagen',
  };
  final age = n.turning == null
      ? null
      : (n.isToday ? 'wird heute ${n.turning}' : 'wird ${n.turning}');
  return HeroText(
    when,
    displayName(p),
    [if (age != null) age, formatLong(n.date)].join(' · '),
  );
}
