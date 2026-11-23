import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ai_service.dart';
import '../data/greeting_service.dart';
import '../data/share_bridge.dart';
import '../theme/tokens.dart';
import 'motion.dart';

/// Ask the shell to show a tab (4 = «Mehr»).
final tabRequest = ValueNotifier<int?>(null);

/// Bumped whenever the visible tab changes, so the banner checks again.
final setupRefresh = ValueNotifier<int>(0);

/// Shows what is still missing for the app to be dependable (permissions,
/// battery exemption, AI key) and leads to «Mehr», where each is fixed.
/// Invisible when everything is in place.
class SetupBanner extends StatefulWidget {
  const SetupBanner({super.key});

  @override
  State<SetupBanner> createState() => _SetupBannerState();
}

class _SetupBannerState extends State<SetupBanner> with WidgetsBindingObserver {
  var _missing = const <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    setupRefresh.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    setupRefresh.removeListener(_check);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final missing = <String>[];
    try {
      final st = await GreetingService.instance.status();
      if (!st.notifications) missing.add('Benachrichtigungen erlauben');
      if (!st.exact) missing.add('pünktliche Erinnerungen erlauben');
      if (!await ShareBridge.batteryUnrestricted()) missing.add('Akku-Ausnahme setzen');
      if (await Secrets.apiKey() == null) missing.add('KI-Schlüssel eintragen');
    } catch (_) {
      return; // No service (tests): show nothing.
    }
    if (mounted) setState(() => _missing = missing);
  }

  @override
  Widget build(BuildContext context) {
    if (_missing.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Nl.s4, Nl.s3, Nl.s4, 0),
      child: PressScale(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            tabRequest.value = 4;
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Nl.s4, vertical: Nl.s3),
            decoration: BoxDecoration(
              color: Nl.personAmber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Nl.rM),
              border: Border.all(color: Nl.personAmber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 20, color: Nl.personAmber),
                const SizedBox(width: Nl.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Einrichtung abschliessen',
                          style: Nl.bodySmall.copyWith(color: Nl.ink)),
                      Text(_missing.join(' · '), style: Nl.caption),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Nl.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
