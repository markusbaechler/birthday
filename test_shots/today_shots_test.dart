// Renders real screens to PNG (build/shots) so the design can be checked
// before a build goes to the phone. Not part of the normal test run.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geburtstage/data/database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geburtstage/main.dart';
import 'package:geburtstage/theme/app_theme.dart';
import 'package:geburtstage/ui/ambient.dart';
import 'package:geburtstage/ui/format.dart';
import 'package:geburtstage/ui/calendar_screen.dart';
import 'package:geburtstage/ui/greeting_editor.dart';
import 'package:geburtstage/ui/people_screen.dart';
import 'package:geburtstage/ui/planner_screen.dart';
import 'package:geburtstage/ui/today_screen.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geburtstage/ui/settings_screen.dart';
import 'package:drift/native.dart';

Future<void> _font(String family, String path) async {
  final f = File(path);
  if (!f.existsSync()) {
    // ignore: avoid_print
    print('Font missing: $path');
    return;
  }
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await loader.load();
}

Person _p(int id, String first, String last, int d, int m, int? y, int color,
        {String? nickname}) =>
    Person(
      id: id,
      firstName: first,
      lastName: last,
      nickname: nickname,
      birthDay: d,
      birthMonth: m,
      birthYear: y,
      channel: Channels.whatsapp,
      insiders: '',
      colorIndex: color,
      createdAt: DateTime(2026),
    );

Greeting _g(int personId, String status, {DateTime? at}) => Greeting(
      id: personId,
      personId: personId,
      year: 2026,
      draft: 'Liebe …',
      channel: Channels.whatsapp,
      status: status,
      createdAt: DateTime(2026),
      scheduledAt: at,
    );

final _today = DateTime(2026, 11, 22, 14);

final _people = [
  _p(1, 'Silvia', 'Meier', 28, 11, 1982, 0),
  _p(2, 'Markus', 'Bächler', 3, 12, 1979, 1),
  _p(3, 'Mia', 'Huber', 9, 12, 2015, 2),
  _p(4, 'Peter', 'Brunner', 17, 12, 1956, 1),
  _p(5, 'Claudia', '(Gotte)', 2, 1, null, 2),
  _p(6, 'Philippa-Charlotte', 'Müller-Lüdenscheidt', 14, 1, 1990, 0),
];

Future<void> _shot(WidgetTester tester, String name, Widget body,
    {int nav = 0, AppDatabase? db, double height = 2340,
    Future<void> Function(WidgetTester)? before}) async {
  tester.view.physicalSize = Size(1080, height);
  tester.view.devicePixelRatio = 2.625;
  tester.view.padding = const FakeViewPadding(top: 105, bottom: 50);
  tester.view.viewPadding = const FakeViewPadding(top: 105, bottom: 50);
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  final app = MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('de', 'CH'),
      supportedLocales: const [Locale('de', 'CH'), Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: nav < 0
          ? body
          : Scaffold(
              extendBody: true,
              body: SafeArea(bottom: false, child: body),
              bottomNavigationBar: GlassNavBar(index: nav, onSelect: (_) {}),
            ),
  );
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: db == null ? app : AppScope(db: db, child: app),
  ));
  if (before != null) await before(tester);
  // Let entrance animations finish.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.625);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/shots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
  // Let drift's stream clean-up timers run out.
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(() async {
    Ambient.sensorsEnabled = false;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    const flex = 'assets/fonts/RobotoFlex.ttf';
    await _font('RobotoFlex', flex);
    await _font('Roboto', flex);
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      await _font('MaterialIcons',
          '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    }
  });

  testWidgets('heute: nächster in 6 Tagen', (tester) async {
    await _shot(
      tester,
      '01_heute',
      TodayView(
        today: _today,
        cards: upcomingFor(_people, _today),
        greetings: const {},
        celebrate: false,
      ),
    );
  });

  testWidgets('heute: Geburtstag heute', (tester) async {
    final people = [
      _p(7, 'Lena', 'Keller', 22, 11, 1996, 0),
      ..._people,
    ];
    await _shot(
      tester,
      '02_heute_geburtstag',
      TodayView(
        today: _today,
        cards: upcomingFor(people, _today),
        greetings: const {},
        celebrate: false,
      ),
    );
  });

  testWidgets('heute: Gruss geplant, langer Name', (tester) async {
    final people = [_people[5], _people[1]];
    await _shot(
      tester,
      '03_langer_name_geplant',
      TodayView(
        today: _today,
        cards: upcomingFor(people, _today)
          ..sort((a, b) => b.next.daysUntil.compareTo(a.next.daysUntil)),
        greetings: {
          '6-2027': _g(6, GreetingStatus.scheduled,
              at: DateTime(2027, 1, 14, 9)),
        },
        celebrate: false,
      ),
    );
  });

  Future<(AppDatabase, Person)> seed(WidgetTester tester,
      {bool withImage = false}) async {
    String? imagePath;
    if (withImage) {
      await tester.runAsync(() async {
        final rec = ui.PictureRecorder();
        final c = Canvas(rec);
        const size = Size(800, 1000);
        c.drawRect(
            Offset.zero & size,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF4D9C6), Color(0xFFE9A7C0), Color(0xFF7A6FB0)],
              ).createShader(Offset.zero & size));
        c.drawCircle(const Offset(400, 430), 220,
            Paint()..color = const Color(0x88FFFFFF));
        final img = await rec.endRecording().toImage(800, 1000);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        final f = File('build/tmp/card.png')..createSync(recursive: true);
        f.writeAsBytesSync(png!.buffer.asUint8List());
        imagePath = f.absolute.path;
        // Decode now, outside the fake clock, so the editor finds it cached.
        final done = Completer<void>();
        FileImage(File(imagePath!)).resolve(ImageConfiguration.empty).addListener(
            ImageStreamListener((_, __) => done.complete(),
                onError: (e, s) => done.completeError(e)));
        await done.future;
      });
    }
    // The database lives in the test zone, so pumping drives its futures.
    final db = AppDatabase(NativeDatabase.memory());
    final id = await db.into(db.people).insert(PeopleCompanion.insert(
          firstName: 'Silvia',
          lastName: const Value('Meier'),
          birthDay: 28,
          birthMonth: 11,
          birthYear: const Value(1982),
          phone: const Value('+41791234567'),
          relation: const Value('Schwester'),
          tone: const Value('herzlich, ein bisschen frech'),
          insiders: const Value('Velotour an den Bodensee\nimmer zu spät'),
        ));
    final person = (await db.allPeople()).firstWhere((x) => x.id == id);
    await db.saveGreeting(
      personId: id,
      year: 2026,
      channel: Channels.whatsapp,
      draft: const Value(
          'Silvia, 44 und immer noch die Einzige, die zu spät zur eigenen Velotour kommt. Ich warte gern wieder am Bodensee auf dich. Hab einen wunderbaren Tag!'),
      variants: const Value(
          '[{"title":"Velotour","text":"a"},{"title":"Zu spät","text":"b"},{"title":"Schwester","text":"c"}]'),
      imagePrompt: const Value(
          'Gestalte eine Geburtstagskarte im Hochformat 4:5 im Risographie-Stil: zwei Velos auf einem Uferweg am Bodensee in der Abendsonne, ein Velo steht schon, das andere kommt eilig angefahren, eine kleine Taschenuhr am Lenker. Warme Pastelltöne, feine Körnung, viel Luft. Einziger Text, korrekt geschrieben: «Alles Gute, Silvia».'),
      imagePath: Value(imagePath),
    );
    return (db, person);
  }

  testWidgets('gruss: Editor mit Prompt', timeout: const Timeout(Duration(seconds: 90)), (tester) async {
    final (db, person) = await seed(tester);
    await _shot(tester, '04_gruss_editor',
        GreetingEditor(person: person, autoGenerate: false),
        nav: -1, db: db, height: 4400);
    await db.close();
  });

  testWidgets('gruss: Editor mit Bild', timeout: const Timeout(Duration(seconds: 90)), (tester) async {
    final (db, person) = await seed(tester, withImage: true);
    await _shot(tester, '05_gruss_mit_bild',
        GreetingEditor(person: person, autoGenerate: false),
        nav: -1, db: db, height: 4400);
    await db.close();
  });

  Future<AppDatabase> seedMany() async {
    final db = AppDatabase(NativeDatabase.memory());
    final ids = <String, int>{};
    for (final (f, l, d, m, y) in [
      ('Silvia', 'Meier', 28, 11, 1982),
      ('Markus', 'Bächler', 3, 12, 1979),
      ('Mia', 'Huber', 9, 12, 2015),
      ('Peter', 'Brunner', 17, 12, 1956),
      ('Claudia', '(Gotte)', 2, 1, null),
      ('Lena', 'Keller', 22, 11, 1996),
    ]) {
      ids[f] = await db.addPerson(PeopleCompanion.insert(
        firstName: f,
        lastName: Value(l),
        birthDay: d,
        birthMonth: m,
        birthYear: Value(y),
      ));
    }
    await db.saveGreeting(
      personId: ids['Silvia']!,
      year: 2026,
      channel: Channels.whatsapp,
      draft: const Value('Silvia, 44 und immer noch die Einzige, die zu spät zur eigenen Velotour kommt. Hab einen wunderbaren Tag!'),
      status: const Value(GreetingStatus.scheduled),
      scheduledAt: Value(DateTime(2026, 11, 28, 9)),
    );
    await db.saveGreeting(
      personId: ids['Peter']!,
      year: 2026,
      channel: Channels.whatsapp,
      draft: const Value('Lieber Peter, 70 Jahre – und noch immer der Erste auf dem Gipfel.'),
      status: const Value(GreetingStatus.scheduled),
      scheduledAt: Value(DateTime(2026, 12, 17, 8, 30)),
    );
    await db.saveGreeting(
      personId: ids['Markus']!,
      year: 2026,
      channel: Channels.whatsapp,
      draft: const Value('Markus, alles Gute!'),
    );
    return db;
  }

  for (final (name, screen) in [
    ('06_gruesse', const PlannerScreen()),
    ('07_kalender', const CalendarScreen()),
    ('08_personen', const PeopleScreen()),
    ('09_mehr', const SettingsScreen()),
  ]) {
    testWidgets('liste: $name', timeout: const Timeout(Duration(seconds: 90)), (tester) async {
      final db = await seedMany();
      await _shot(tester, name, screen,
          nav: name.startsWith('06') ? 2 : name.startsWith('07') ? 1 : name.startsWith('09') ? 4 : 3,
          db: db, height: name.startsWith('09') ? 3400 : 2340);
    });
  }
}
