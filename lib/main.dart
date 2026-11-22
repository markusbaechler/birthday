import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/database.dart';
import 'data/greeting_service.dart';
import 'data/photo_sync.dart';
import 'data/widget_sync.dart';
import 'theme/app_theme.dart';
import 'ui/calendar_screen.dart';
import 'ui/people_screen.dart';
import 'ui/planner_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/today_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  WidgetSync(db).start();
  try {
    await GreetingService.init(db);
  } catch (e) {
    debugPrint('Greeting service failed: $e');
  }
  runApp(GeburtstageApp(db: db));
  // Photos follow the contacts automatically, a moment after start.
  Future.delayed(const Duration(seconds: 3), () => PhotoSync(db).run());
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
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: const [
            TodayScreen(),
            CalendarScreen(),
            PlannerScreen(),
            PeopleScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: GlassNavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Frosted glass navigation: content glides underneath.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF0E0C12).withValues(alpha: 0.72),
              border: const Border(top: BorderSide(color: Color(0xFF1F1B25))),
            ),
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              selectedIndex: index,
              onDestinationSelected: (i) {
                HapticFeedback.selectionClick();
                onSelect(i);
              },
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.cake_outlined), label: 'Heute'),
                NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined), label: 'Kalender'),
                NavigationDestination(
                    icon: Icon(Icons.edit_note), label: 'Grüsse'),
                NavigationDestination(
                    icon: Icon(Icons.people_outline), label: 'Personen'),
                NavigationDestination(
                    icon: Icon(Icons.tune), label: 'Mehr'),
              ],
            ),
          ),
        ),
      );
}
