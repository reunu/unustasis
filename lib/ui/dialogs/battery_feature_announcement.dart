import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import '../../feature_flags.dart';
import '../../service/battery_onboarding_preferences.dart';
import '../screens/battery_tracker_screen.dart';
import '../widgets/battery_tracking_intro.dart';
import '../widgets/primary_button.dart';

Future<bool> showBatteryFeatureAnnouncement(
  BuildContext context, {
  required bool Function() canShow,
  BatteryOnboardingPreferences? preferences,
  Future<void> Function()? openTracker,
  bool enabled = sunshineBatteryRegistrationEnabled,
}) async {
  if (!enabled) return true;
  if (!context.mounted || !canShow()) return false;
  final onboarding = preferences ?? BatteryOnboardingPreferences();
  final alreadySeen = await onboarding.hasSeenBatteryFeature();
  if (!context.mounted || !canShow()) return false;
  if (alreadySeen) return true;
  final addBattery = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(28, 12, 28, 24 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BatteryTrackingIntro(registrationEnabled: enabled),
          const SizedBox(height: 32),
          PrimaryButton(
            text: FlutterI18n.translate(context, 'battery_tracker_add'),
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 8),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: () => Navigator.pop(context, false),
            child: Text(FlutterI18n.translate(context, 'battery_tracker_not_now')),
          ),
        ]),
      ),
    ),
  );
  if (addBattery == true && (!context.mounted || !canShow())) return false;
  await onboarding.markBatteryFeatureSeen();
  if (addBattery == true && context.mounted && canShow()) {
    if (openTracker != null) {
      await openTracker();
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BatteryTrackerScreen(startWithScan: true, registrationEnabled: enabled),
      ));
    }
  }
  return true;
}
