import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../theme/tokens.dart';

/// A person's loud colour: every card is a poster in it.
class Poster {
  const Poster(this.bg, this.deep);

  /// The poster's main colour.
  final Color bg;

  /// A darker shade of it, for the giant numeral and for text on white.
  final Color deep;

  static const all = [
    Poster(Color(0xFFE4572E), Color(0xFFAE3513)), // coral
    Poster(Color(0xFF0E7C7B), Color(0xFF075453)), // petrol
    Poster(Color(0xFF6C4CE0), Color(0xFF462BB0)), // violet
    Poster(Color(0xFFD98A0B), Color(0xFFA05F00)), // amber
    Poster(Color(0xFFD0407F), Color(0xFF9A2157)), // magenta
    Poster(Color(0xFF2D6CDF), Color(0xFF1848A8)), // blue
    Poster(Color(0xFF3E9B4F), Color(0xFF226B34)), // green
  ];

  /// A lighter tone, readable as text or line on the dark app background.
  Color get light => Color.lerp(bg, Colors.white, 0.38)!;

  static Poster of(Person p) => all[p.id % all.length];
}

/// The poster itself: colour, a soft light that follows the device tilt and
/// a giant [figure] (the age, or the first letter) cropped by the edge.
class PosterBackdrop extends StatelessWidget {
  const PosterBackdrop({
    super.key,
    required this.poster,
    required this.figure,
    this.parallax = 0,
    this.tilt,
  });

  final Poster poster;
  final String figure;

  /// -1 … 1 while swiping: the figure moves against the card.
  final double parallax;
  final ValueListenable<Offset>? tilt;

  static final _flat = ValueNotifier<Offset>(Offset.zero);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: tilt ?? _flat,
      builder: (context, tl, _) => Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [poster.bg, Color.lerp(poster.bg, poster.deep, 0.75)!],
              ),
            ),
          ),
          // Light from the top left.
          Positioned(
            left: -140 + tl.dx * 40,
            top: -160 + tl.dy * 30,
            width: 460,
            height: 460,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Colors.white.withValues(alpha: 0.22),
                  Colors.white.withValues(alpha: 0),
                ]),
              ),
            ),
          ),
          Positioned(
            right: -26 - parallax * 70 - tl.dx * 22,
            top: -44 - tl.dy * 16,
            child: Text(
              figure,
              softWrap: false,
              style: Nl.display(figure.length > 2 ? 250 : 330,
                  weight: 800,
                  color: poster.deep.withValues(alpha: 0.62),
                  height: 1,
                  spacing: -16),
            ),
          ),
        ],
      ),
    );
  }
}
