import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// Keeps the home screen widgets in sync with the database.
/// Passes name, birthday, colour and the path of a photo file; the widgets
/// compute the days themselves and draw everything natively.
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

  /// Writes photos as files the widget can read; skips unchanged ones.
  Future<Map<int, String>> _writePhotos(List<Person> people) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/widget_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    final paths = <int, String>{};
    for (final p in people) {
      final photo = p.photo;
      if (photo == null || photo.isEmpty) continue;
      final file = File('${dir.path}/${p.id}.img');
      if (!await file.exists() || await file.length() != photo.length) {
        await file.writeAsBytes(photo, flush: true);
      }
      paths[p.id] = file.path;
    }
    return paths;
  }

  Future<void> _push(List<Person> people) async {
    try {
      final photos = await _writePhotos(people);
      final data = [
        for (final p in people)
          {
            'n': (p.nickname?.trim().isNotEmpty ?? false)
                ? p.nickname!.trim()
                : p.firstName,
            'f': '${p.firstName} ${p.lastName}'.trim(),
            'd': p.birthDay,
            'm': p.birthMonth,
            'y': p.birthYear,
            'c': p.colorIndex,
            'p': photos[p.id],
          }
      ];
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
