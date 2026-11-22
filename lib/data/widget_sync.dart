import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'database.dart';

/// Keeps the home screen widgets in sync with the database.
/// Only name, birthday and colour are passed; the widgets compute the days.
class WidgetSync {
  WidgetSync(this.db);
  final AppDatabase db;
  StreamSubscription<List<Person>>? _sub;

  static const _providers = [
    'ch.markusbaechler.geburtstage.LargeBirthdayWidget',
    'ch.markusbaechler.geburtstage.SmallBirthdayWidget',
  ];

  void start() {
    _sub ??= db.watchPeople().listen(_push);
  }

  Future<void> _push(List<Person> people) async {
    final data = [
      for (final p in people)
        {
          'n': (p.nickname?.trim().isNotEmpty ?? false)
              ? p.nickname!.trim()
              : p.firstName,
          'd': p.birthDay,
          'm': p.birthMonth,
          'y': p.birthYear,
          'c': p.colorIndex,
        }
    ];
    try {
      await HomeWidget.saveWidgetData<String>('people', jsonEncode(data));
      for (final provider in _providers) {
        await HomeWidget.updateWidget(qualifiedAndroidName: provider);
      }
    } catch (e) {
      // Widgets are optional; never break the app because of them.
      debugPrint('Widget update failed: $e');
    }
  }

  Future<void> dispose() async => _sub?.cancel();
}
