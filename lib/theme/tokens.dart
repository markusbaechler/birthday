import 'package:flutter/material.dart';

/// Design tokens from the design system «Nacht, leiser».
abstract final class Nl {
  // Colour
  static const bg = Color(0xFF0E0C12);
  static const surface = Color(0xFF16131B);
  static const surfaceRaised = Color(0xFF17141D);
  static const border = Color(0xFF241F2B);
  static const borderControl = Color(0xFF3A3342);
  static const borderIcon = Color(0xFF2A2532);
  static const divider = Color(0xFF1F1B25);
  static const ringOuter = Color(0xFF221D29);
  static const ringInner = Color(0xFF1A1620);
  static const ink = Color(0xFFECE7F2);
  static const inkBody = Color(0xFFE4DEEC);
  static const inkSoft = Color(0xFFCFC8DA);
  static const muted = Color(0xFF9C95A8);
  static const accent = Color(0xFFE9A7C0);
  static const onAccent = Color(0xFF1E0F16);
  static const personBlue = Color(0xFF8FB4E8);
  static const personGreen = Color(0xFF8FD0AA);
  static const personAmber = Color(0xFFE3C27A);
  static const dangerInk = Color(0xFFF0B4AE);
  static const dangerBorder = Color(0xFF5A3A3A);

  /// Person colours by colorIndex. Rosé is reserved for "today".
  static const personColors = [personBlue, personGreen, personAmber];

  static Color personColor(int index, {bool today = false}) =>
      today ? accent : personColors[index % personColors.length];

  // Spacing (4 px grid)
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;

  // Radius
  static const rS = 12.0;
  static const rM = 20.0;
  static const rL = 24.0;
  static const rXl = 28.0;

  // Type
  /// Display face with character: Fraunces (variable, soft optical sizes).
  static const displayFamily = 'Fraunces';

  /// Display text in Fraunces. [weight] drives the variable axis.
  static TextStyle display(double size,
          {double weight = 300, Color color = ink, double? height, double? spacing}) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        height: height,
        letterSpacing: spacing,
        color: color,
        fontVariations: [
          FontVariation('wght', weight),
          FontVariation('opsz', size.clamp(9, 144).toDouble()),
          const FontVariation('SOFT', 100),
        ],
      );

  static const countdown = TextStyle(
      fontFamily: displayFamily,
      fontSize: 156, height: 136 / 156, fontWeight: FontWeight.w300,
      letterSpacing: -4,
      fontVariations: [
        FontVariation('wght', 260),
        FontVariation('opsz', 144),
        FontVariation('SOFT', 100),
      ],
      fontFeatures: [FontFeature.liningFigures()]);
  static const draft = TextStyle(
      fontSize: 26, height: 36 / 26, fontWeight: FontWeight.w300, color: ink);
  static const numberList =
      TextStyle(fontSize: 26, height: 30 / 26, fontWeight: FontWeight.w300, color: ink);
  static const title = TextStyle(
      fontFamily: displayFamily, fontSize: 28, height: 34 / 28,
      fontWeight: FontWeight.w400, color: ink,
      fontVariations: [FontVariation('wght', 360), FontVariation('opsz', 36), FontVariation('SOFT', 100)]);
  static const lead =
      TextStyle(fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w300, color: inkSoft);
  static const body =
      TextStyle(fontSize: 15.5, height: 24 / 15.5, fontWeight: FontWeight.w400, color: inkBody);
  static const bodySmall =
      TextStyle(fontSize: 14, height: 21 / 14, fontWeight: FontWeight.w300, color: inkSoft);
  static const caption =
      TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400, color: muted);
  static const button =
      TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w500);
  static const label = TextStyle(
      fontSize: 11.5, height: 16 / 11.5, fontWeight: FontWeight.w500,
      letterSpacing: 1.6, color: muted);
}
