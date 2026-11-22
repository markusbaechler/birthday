import 'dart:ui' show Color;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../domain/dedupe.dart';
import 'database.dart';

/// Plans greetings: a notification at the chosen time carries the ready
/// text; tapping it (or «Senden») opens WhatsApp, SMS or e-mail with the
/// text filled in. The user only taps «Senden» there.
class GreetingService {
  GreetingService._(this.db);
  static GreetingService? _instance;
  static GreetingService get instance => _instance!;

  final AppDatabase db;
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationDetails(
    'greetings',
    'Geplante Glückwünsche',
    channelDescription: 'Erinnerung mit fertigem Gruss zur geplanten Zeit',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    color: Color(0xFFE9A7C0),
    styleInformation: BigTextStyleInformation(''),
    actions: [
      AndroidNotificationAction('send', 'Senden', showsUserInterface: true),
    ],
  );

  static Future<GreetingService> init(AppDatabase db) async {
    final s = GreetingService._(db);
    _instance = s;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Zurich'));
    await s._plugin.initialize(
      const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => s._handle(r.payload),
    );
    final launch = await s._plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      await s._handle(launch!.notificationResponse?.payload);
    }
    await s.rescheduleAll();
    return s;
  }

  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final notify = await android?.requestNotificationsPermission() ?? true;
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
    return notify;
  }

  /// Schedules (or re-schedules) the notification of [g].
  Future<void> schedule(Greeting g, Person p) async {
    final when = g.scheduledAt;
    if (when == null || g.draft == null) return;
    if (when.isBefore(DateTime.now())) return;
    final age = p.birthYear == null ? '' : ' (${g.year - p.birthYear!})';
    final name = (p.nickname?.trim().isNotEmpty ?? false) ? p.nickname!.trim() : p.firstName;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.channelId,
        _channel.channelName,
        channelDescription: _channel.channelDescription,
        importance: _channel.importance,
        priority: _channel.priority,
        category: _channel.category,
        color: _channel.color,
        styleInformation: BigTextStyleInformation(g.draft!),
        actions: _channel.actions,
      ),
    );
    final at = tz.TZDateTime.from(when, tz.local);
    try {
      await _plugin.zonedSchedule(
        g.id,
        'Geburtstag von $name$age',
        g.draft,
        at,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: '${g.id}',
      );
    } catch (e) {
      // No exact alarms allowed: still remind, a few minutes off at most.
      await _plugin.zonedSchedule(
        g.id,
        'Geburtstag von $name$age',
        g.draft,
        at,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: '${g.id}',
      );
    }
  }

  Future<void> cancel(int greetingId) => _plugin.cancel(greetingId);

  Future<void> rescheduleAll() async {
    try {
      for (final g in await db.scheduledGreetings()) {
        final p = await (db.select(db.people)
              ..where((x) => x.id.equals(g.personId)))
            .getSingleOrNull();
        if (p != null) await schedule(g, p);
      }
    } catch (e) {
      debugPrint('Reschedule failed: $e');
    }
  }

  Future<void> _handle(String? payload) async {
    final id = int.tryParse(payload ?? '');
    if (id == null) return;
    final g = await db.greetingById(id);
    if (g == null) return;
    final p = await (db.select(db.people)..where((x) => x.id.equals(g.personId)))
        .getSingleOrNull();
    if (p == null) return;
    await send(g, p);
  }

  /// Opens the chat with the text filled in and marks the greeting as sent.
  Future<bool> send(Greeting g, Person p) async {
    final text = g.draft ?? '';
    final uri = sendUri(p, text);
    if (uri == null) return false;
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (ok) {
      await cancel(g.id);
      await db.saveGreeting(
        personId: g.personId,
        year: g.year,
        channel: g.channel,
        sentText: Value(text),
        status: const Value(GreetingStatus.sent),
      );
    }
    return ok;
  }

  static Uri? sendUri(Person p, String text) {
    final phone = normalizePhone(p.phone);
    switch (p.channel) {
      case Channels.whatsapp when phone != null:
        return Uri.parse(
            'https://wa.me/${phone.substring(1)}?text=${Uri.encodeComponent(text)}');
      case Channels.sms when phone != null:
        return Uri.parse('sms:$phone?body=${Uri.encodeComponent(text)}');
      case Channels.email when (p.email?.isNotEmpty ?? false):
        return Uri.parse('mailto:${p.email}?body=${Uri.encodeComponent(text)}');
    }
    if (phone != null) {
      return Uri.parse(
          'https://wa.me/${phone.substring(1)}?text=${Uri.encodeComponent(text)}');
    }
    return null;
  }
}
