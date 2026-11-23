import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/database.dart';
import 'data/greeting_service.dart';
import 'data/backup_service.dart';
import 'data/photo_sync.dart';
import 'data/share_bridge.dart';
import 'data/widget_sync.dart';
import 'theme/app_theme.dart';
import 'ui/calendar_screen.dart';
import 'ui/format.dart';
import 'ui/greeting_editor.dart';
import 'ui/people_screen.dart';
import 'ui/planner_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/setup_banner.dart';
import 'ui/share_sheet.dart';
import 'ui/today_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  WidgetSync(db).start();
  BackupService.watch(db);
  try {
    await GreetingService.init(db);
  } catch (e) {
    debugPrint('Greeting service failed: $e');
  }
  await ShareBridge.init();
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  var _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShareBridge.incoming.addListener(_onShare);
    GreetingService.openPerson.addListener(_onReminder);
    tabRequest.addListener(_onTab);
    Future.delayed(const Duration(seconds: 6), _backup);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onShare();
      _onReminder();
      _askForNotifications();
    });
  }

  void _onTab() {
    final t = tabRequest.value;
    if (t == null || !mounted) return;
    tabRequest.value = null;
    setState(() => _index = t);
  }

  // Leaving the app: secure what changed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _backup();
  }

  void _backup() {
    if (!mounted) return;
    BackupService(AppScope.of(context)).autoBackup();
  }

  /// Reminders need the permission; ask as soon as there is someone to
  /// be reminded of.
  Future<void> _askForNotifications() async {
    try {
      if ((await AppScope.of(context).allPeople()).isEmpty) return;
      await GreetingService.instance.requestPermissions();
    } catch (_) {}
  }

  /// A birthday reminder was tapped: open that person's greeting.
  Future<void> _onReminder() async {
    final id = GreetingService.openPerson.value;
    if (id == null || !mounted) return;
    GreetingService.openPerson.value = null;
    final people = await AppScope.of(context).allPeople();
    final person = people.where((p) => p.id == id).firstOrNull;
    if (person == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GreetingEditor(person: person)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShareBridge.incoming.removeListener(_onShare);
    GreetingService.openPerson.removeListener(_onReminder);
    tabRequest.removeListener(_onTab);
    super.dispose();
  }

  /// Text or an image arrived from another app: ask for whom, then open
  /// that person's greeting with it.
  Future<void> _onShare() async {
    final shared = ShareBridge.incoming.value;
    if (shared == null || !mounted) return;
    ShareBridge.incoming.value = null;
    final db = AppScope.of(context);
    final people = await db.allPeople();
    if (!mounted) return;
    if (people.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Erst Personen erfassen, dann klappt das Teilen.')));
      return;
    }
    final chosen = await showModalBottomSheet<Person>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SharePersonSheet(
          cards: upcomingFor(people, DateTime.now()), shared: shared),
    );
    if (chosen == null || !mounted) return;
    // One editor at a time: a share replaces whatever was open.
    Navigator.of(context).popUntil((r) => r.isFirst);
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GreetingEditor(person: chosen, incoming: shared)));
  }

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
        onSelect: (i) {
          setState(() => _index = i);
          setupRefresh.value++;
        },
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
                    icon: Icon(Icons.cake_outlined), label: 'Demnächst'),
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
