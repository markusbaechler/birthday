import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide Person;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../domain/birthday.dart';
import '../domain/dedupe.dart';
import 'database.dart';
import 'share_bridge.dart';

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
    await s.rescheduleReminders();
    // Keep reminders in step with people and greetings.
    void changed(Object? _) {
      s._debounce?.cancel();
      s._debounce = Timer(const Duration(seconds: 2), s.rescheduleReminders);
    }

    db.watchPeople().skip(1).listen(changed);
    db.watchGreetings().skip(1).listen(changed);
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
    final hasText = (g.draft ?? '').trim().isNotEmpty;
    if (when == null || (!hasText && g.imagePath == null)) return;
    final body = hasText ? g.draft! : 'Die Karte ist bereit.';
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
        styleInformation: BigTextStyleInformation(body),
        actions: _channel.actions,
      ),
    );
    final at = tz.TZDateTime.from(when, tz.local);
    try {
      await _plugin.zonedSchedule(
        g.id,
        'Geburtstag von $name$age',
        body,
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
        body,
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

  // ---------------------------------------------------------- Reminders

  Timer? _debounce;

  /// A reminder was tapped: the person whose greeting should open.
  static final openPerson = ValueNotifier<int?>(null);

  static const _reminderBase = 1000000;
  static const _testId = 999999;

  static const _reminderDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'birthdays',
      'Geburtstage',
      channelDescription: 'Erinnerung am Vorabend und am Geburtstag',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      color: Color(0xFFE9A7C0),
    ),
  );

  Future<void> _zoned(int id, String title, String body, DateTime when,
      NotificationDetails details, String payload) async {
    final at = tz.TZDateTime.from(when, tz.local);
    try {
      await _plugin.zonedSchedule(id, title, body, at, details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: payload);
    } catch (e) {
      await _plugin.zonedSchedule(id, title, body, at, details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload);
    }
  }

  /// Every birthday gets a reminder, with or without a greeting: on the eve
  /// and in the morning, plus the morning of the year after, so reminders
  /// keep coming even if the app is not opened for a long time.
  Future<void> rescheduleReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = ReminderSettings.read(prefs);
      for (final r in await _plugin.pendingNotificationRequests()) {
        if (r.id >= _reminderBase) await _plugin.cancel(r.id);
      }
      final now = DateTime.now();
      final greetings = {
        for (final g in await db.select(db.greetings).get())
          '${g.personId}-${g.year}': g
      };
      final people = await db.allPeople();
      final next = {
        for (final p in people)
          p.id: nextBirthday(
              day: p.birthDay, month: p.birthMonth, year: p.birthYear, today: now)
      };
      people.sort((a, b) => next[a.id]!.daysUntil.compareTo(next[b.id]!.daysUntil));
      var budget = 420; // Android allows 500 alarms per app.
      for (final p in people) {
        if (budget < 3) break;
        final n = next[p.id]!;
        final d = n.date;
        final name = (p.nickname?.trim().isNotEmpty ?? false)
            ? p.nickname!.trim()
            : '${p.firstName} ${p.lastName}'.trim();
        final g = greetings['${p.id}-${d.year}'];
        final sent = g?.status == GreetingStatus.sent;
        final planned = g?.status == GreetingStatus.scheduled && g?.scheduledAt != null;
        final hasDraft = (g?.draft ?? '').trim().isNotEmpty || g?.imagePath != null;
        final turns = n.turning == null ? '' : ' wird ${n.turning}';
        final id = _reminderBase + p.id * 10;

        if (settings.eve && !sent) {
          final at = DateTime(d.year, d.month, d.day - 1, settings.eveHour, settings.eveMinute);
          if (at.isAfter(now)) {
            final state = planned
                ? 'Gruss ist geplant für ${_hm(g!.scheduledAt!)}.'
                : hasDraft
                    ? 'Entwurf liegt bereit, noch nicht geplant.'
                    : 'Noch kein Gruss vorbereitet. Tippen zum Schreiben.';
            await _zoned(id, 'Morgen: $name$turns', state, at, _reminderDetails, 'p:${p.id}');
            budget--;
          }
        }
        // The planned greeting itself is the reminder of the day.
        if (settings.day && !sent && !planned) {
          final at = DateTime(d.year, d.month, d.day, settings.dayHour, settings.dayMinute);
          if (at.isAfter(now)) {
            await _zoned(
                id + 1,
                'Heute: $name$turns',
                hasDraft ? 'Dein Entwurf liegt bereit. Tippen zum Senden.' : 'Tippen, um zu gratulieren.',
                at,
                _reminderDetails,
                'p:${p.id}');
            budget--;
          }
        }
        if (settings.day) {
          final ny = occurrenceIn(d.year + 1, p.birthMonth, p.birthDay);
          final age = p.birthYear == null ? '' : ' wird ${ny.year - p.birthYear!}';
          await _zoned(
              id + 2,
              'Heute: $name$age',
              'Tippen, um zu gratulieren.',
              DateTime(ny.year, ny.month, ny.day, settings.dayHour, settings.dayMinute),
              _reminderDetails,
              'p:${p.id}');
          budget--;
        }
      }
    } catch (e) {
      debugPrint('Reminders failed: $e');
    }
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// A real alarm one minute ahead: proves that reminders arrive even with
  /// the screen off.
  Future<void> scheduleTest() => _zoned(
      _testId,
      'Test bestanden',
      'Erinnerungen kommen auf diesem Handy pünktlich an.',
      DateTime.now().add(const Duration(minutes: 1)),
      _reminderDetails,
      '');

  /// What Android currently allows.
  Future<({bool notifications, bool exact})> status() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return (
      notifications: await android?.areNotificationsEnabled() ?? true,
      exact: await android?.canScheduleExactNotifications() ?? true,
    );
  }

  Future<int> pendingReminders() async =>
      (await _plugin.pendingNotificationRequests())
          .where((r) => r.id >= _reminderBase)
          .length;

  Future<void> _handle(String? payload) async {
    if (payload != null && payload.startsWith('p:')) {
      openPerson.value = int.tryParse(payload.substring(2));
      return;
    }
    final id = int.tryParse(payload ?? '');
    if (id == null) return;
    final g = await db.greetingById(id);
    if (g == null) return;
    final p = await (db.select(db.people)..where((x) => x.id.equals(g.personId)))
        .getSingleOrNull();
    if (p == null) return;
    await send(g, p);
  }

  /// Opens the chat with the text (and the card image) filled in and marks
  /// the greeting as sent. With an image: WhatsApp straight into the chat,
  /// other channels through the share sheet.
  Future<bool> send(Greeting g, Person p) async {
    final text = g.draft ?? '';
    final image = g.imagePath != null && File(g.imagePath!).existsSync()
        ? g.imagePath
        : null;
    var ok = false;
    if (image != null) {
      final phone = normalizePhone(p.phone);
      final whatsapp = p.channel == Channels.whatsapp ||
          (p.channel != Channels.email && p.channel != Channels.sms && phone != null);
      ok = whatsapp && phone != null
          ? await ShareBridge.sendWhatsApp(phone: phone, text: text, imagePath: image)
          : await ShareBridge.share(text: text, imagePath: image);
    } else {
      final uri = sendUri(p, text);
      if (uri == null) return false;
      try {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
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

/// When the birthday reminders come.
class ReminderSettings {
  const ReminderSettings({
    this.eve = true,
    this.eveHour = 18,
    this.eveMinute = 0,
    this.day = true,
    this.dayHour = 8,
    this.dayMinute = 0,
  });
  final bool eve;
  final int eveHour;
  final int eveMinute;
  final bool day;
  final int dayHour;
  final int dayMinute;

  static ReminderSettings read(SharedPreferences p) => ReminderSettings(
        eve: p.getBool('rem_eve') ?? true,
        eveHour: p.getInt('rem_eve_h') ?? 18,
        eveMinute: p.getInt('rem_eve_m') ?? 0,
        day: p.getBool('rem_day') ?? true,
        dayHour: p.getInt('rem_day_h') ?? 8,
        dayMinute: p.getInt('rem_day_m') ?? 0,
      );

  Future<void> write(SharedPreferences p) async {
    await p.setBool('rem_eve', eve);
    await p.setInt('rem_eve_h', eveHour);
    await p.setInt('rem_eve_m', eveMinute);
    await p.setBool('rem_day', day);
    await p.setInt('rem_day_h', dayHour);
    await p.setInt('rem_day_m', dayMinute);
  }
}
