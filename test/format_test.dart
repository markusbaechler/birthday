import 'package:flutter_test/flutter_test.dart';
import 'package:geburtstage/data/database.dart';
import 'package:geburtstage/ui/format.dart';

Person _p(String first, String last, {String? nick}) => Person(
      id: 1,
      firstName: first,
      lastName: last,
      nickname: nick,
      birthDay: 1,
      birthMonth: 1,
      channel: Channels.whatsapp,
      insiders: '',
      colorIndex: 0,
      createdAt: DateTime(2026),
    );

void main() {
  test('initials use letters only', () {
    expect(initialsOf(_p('Claudia', '(Gotte)')), 'CG');
    expect(initialsOf(_p('Silvia', 'Meier')), 'SM');
    expect(initialsOf(_p('Ännchen', '')), 'Ä');
    expect(initialsOf(_p('(Chef)', '')), 'C');
  });

  test('line under the first name', () {
    expect(surnameFor(_p('Silvia', 'Meier')), 'Meier');
    expect(surnameFor(_p('Silvia', '')), isNull);
    expect(surnameFor(_p('Silvia', 'Meier', nick: 'Sili')), 'Silvia Meier');
  });
}
