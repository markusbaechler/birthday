import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../data/share_bridge.dart';
import '../theme/tokens.dart';
import 'art.dart';
import 'format.dart';
import 'widgets.dart';

/// «Für wen ist das?» after another app shared text or an image.
/// The next birthdays come first.
class SharePersonSheet extends StatelessWidget {
  const SharePersonSheet({super.key, required this.cards, required this.shared});
  final List<Upcoming> cards;
  final SharedIn shared;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Nl.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Nl.rXl)),
          border: Border(top: BorderSide(color: Nl.border)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(Nl.s5, Nl.s3, Nl.s5, Nl.s6),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Nl.borderControl,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: Nl.s5),
            const Text('Für wen ist das?', style: Nl.title),
            const SizedBox(height: Nl.s4),
            _Preview(shared: shared),
            const SizedBox(height: Nl.s5),
            const SectionLabel('Nächste Geburtstage'),
            const SizedBox(height: Nl.s2),
            for (final u in cards)
              InkWell(
                borderRadius: BorderRadius.circular(Nl.rM),
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop(u.person);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Nl.s2),
                  child: Row(
                    children: [
                      PersonAvatar(
                        person: u.person,
                        size: 44,
                        color: Nl.personColor(u.person.colorIndex,
                            today: u.next.isToday),
                      ),
                      const SizedBox(width: Nl.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fullName(u.person),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Nl.body.copyWith(color: Nl.ink)),
                            Text(
                              '${_cap(inDays(u.next.daysUntil))} · ${formatShort(u.next.date)}',
                              style: Nl.caption.copyWith(
                                  color: u.next.isToday ? Nl.accent : Nl.muted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Nl.borderControl),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _Preview extends StatelessWidget {
  const _Preview({required this.shared});
  final SharedIn shared;

  @override
  Widget build(BuildContext context) {
    final image = shared.imagePath;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(Nl.rS),
            child: Image.file(File(image),
                width: 72, height: 90, fit: BoxFit.cover, cacheWidth: 216),
          ),
        if (image != null && shared.text != null) const SizedBox(width: Nl.s3),
        if (shared.text != null)
          Expanded(
            child: Text(shared.text!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Nl.bodySmall),
          )
        else if (image != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: Nl.s3, top: Nl.s1),
              child: Text('Das Bild wird die Karte zum Gruss.',
                  style: Nl.bodySmall),
            ),
          ),
      ],
    );
  }
}
