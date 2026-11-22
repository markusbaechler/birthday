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
