import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/database.dart';
import 'data/widget_sync.dart';
import 'theme/app_theme.dart';
import 'ui/people_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/today_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  WidgetSync(db).start();
  runApp(GeburtstageApp(db: db));
}

/// Gives every screen access to the database.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.db, required super.child});
  final AppDatabase db;

  static AppDatabase of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.db;

  @override
  bool updateShouldNotify(AppScope oldWidget) => db != oldWidget.db;
}

class GeburtstageApp extends StatelessWidget {
  const GeburtstageApp({super.key, required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      db: db,
      child: MaterialApp(
        title: 'Geburtstage',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(),
        themeMode: ThemeMode.dark,
        locale: const Locale('de', 'CH'),
        supportedLocales: const [Locale('de', 'CH'), Locale('de')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: const [TodayScreen(), PeopleScreen(), SettingsScreen()],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF1F1B25)))),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined), label: 'Heute'),
            NavigationDestination(
                icon: Icon(Icons.people_outline), label: 'Personen'),
            NavigationDestination(
                icon: Icon(Icons.tune), label: 'Einstellungen'),
          ],
        ),
      ),
    );
  }
}
