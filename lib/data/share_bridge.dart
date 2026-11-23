import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Text or an image another app shared with «Geburtstage».
class SharedIn {
  const SharedIn({this.text, this.imagePath});
  final String? text;
  final String? imagePath;

  static SharedIn? from(Object? raw) {
    if (raw is! Map) return null;
    final text = (raw['text'] as String?)?.trim();
    final path = raw['path'] as String?;
    if ((text == null || text.isEmpty) && path == null) return null;
    return SharedIn(text: text?.isEmpty ?? true ? null : text, imagePath: path);
  }
}

/// Native bridge (MainActivity.kt): share target, WhatsApp with image.
abstract final class ShareBridge {
  static const _ch = MethodChannel('geburtstage/share');

  /// The latest share from another app, until it is handled.
  static final incoming = ValueNotifier<SharedIn?>(null);

  static Future<void> init() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'share') incoming.value = SharedIn.from(call.arguments);
    });
    try {
      incoming.value = SharedIn.from(await _ch.invokeMethod('initialShare'));
    } catch (_) {}
  }

  /// WhatsApp straight into the chat of [phone] (E.164), with image.
  /// Falls back to the share sheet.
  static Future<bool> sendWhatsApp(
      {String? phone, required String text, String? imagePath}) async {
    try {
      return await _ch.invokeMethod<bool>('sendWhatsApp',
              {'phone': phone, 'text': text, 'path': imagePath}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Android share sheet with text and optional image.
  static Future<bool> share({required String text, String? imagePath}) async {
    try {
      return await _ch.invokeMethod<bool>(
              'share', {'text': text, 'path': imagePath}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Copies the file at [path] into Download/Geburtstage as [name] and
  /// keeps only the newest [keep] backups there. False on old Android.
  static Future<bool> saveToDownloads(String path, String name, {int keep = 7}) async {
    try {
      return await _ch.invokeMethod<bool>(
              'saveToDownloads', {'path': path, 'name': name, 'keep': keep}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// True when Android does not put the app to sleep.
  static Future<bool> batteryUnrestricted() async {
    try {
      return await _ch.invokeMethod<bool>('batteryUnrestricted') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestBatteryUnrestricted() async {
    try {
      await _ch.invokeMethod('requestBatteryUnrestricted');
    } catch (_) {}
  }

  static Future<void> openAppSettings() async {
    try {
      await _ch.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  /// Hands [text] to the app [package] (e.g. ChatGPT opens a new chat).
  static Future<bool> sendTextToApp(String package, String text) async {
    try {
      return await _ch.invokeMethod<bool>(
              'sendTextToApp', {'package': package, 'text': text}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

/// Card images live in app storage, one per person and year.
abstract final class CardImages {
  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/greeting_images');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Copies [bytes] into storage and returns the new path. A new file name
  /// each time, so image caches never show an old card.
  static Future<String> store(int personId, int year, Uint8List bytes,
      {String extension = 'jpg'}) async {
    final dir = await _dir();
    for (final old in dir.listSync()) {
      if (old.path.split('/').last.startsWith('$personId-$year-')) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
    }
    final ext = extension.toLowerCase().replaceAll('.', '');
    final file = File(
        '${dir.path}/$personId-$year-${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<void> remove(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  static String extensionOf(String path) {
    final i = path.lastIndexOf('.');
    return i < 0 ? 'jpg' : path.substring(i + 1);
  }
}

/// Image AIs the card prompt can go to. The app first hands the prompt to
/// the installed app, otherwise it opens the website.
enum ImageAi {
  chatgpt('ChatGPT', 'com.openai.chatgpt', 'https://chatgpt.com/?q='),
  gemini('Gemini', 'com.google.android.apps.bard', 'https://gemini.google.com/app?q='),
  grok('Grok', 'ai.x.grok', 'https://grok.com/?q=');

  const ImageAi(this.label, this.package, this.web);
  final String label;
  final String package;
  final String web;

  static ImageAi byName(String? name) =>
      ImageAi.values.firstWhere((a) => a.name == name, orElse: () => chatgpt);
}

/// Style presets for the card. [hint] goes into the prompt request.
enum CardStyle {
  auto('Automatisch', null),
  illustration('Illustration', 'Editorial-Illustration mit klaren Flächen und feiner Körnung'),
  photo('Foto', 'fotorealistisch, inszenierte Stillleben- oder Szenenfotografie, 50 mm, geringe Schärfentiefe'),
  clay('3D', '3D-Render, Figuren und Objekte aus matter Knete, weiches Studiolicht'),
  watercolor('Aquarell', 'Aquarell auf rauem Papier mit sichtbaren Pigmenträndern'),
  retro('Retro-Poster', 'Siebdruck-Poster im Stil der 60er-Jahre, wenige Volltonfarben'),
  minimal('Minimal', 'minimalistisch, ein einzelnes starkes Motiv, viel Weissraum'),
  comic('Comic', 'Ligne-claire-Comic mit sauberen Konturen und flachen Farben');

  const CardStyle(this.label, this.hint);
  final String label;
  final String? hint;
}
