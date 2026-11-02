import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import '../../feature_flags.dart';

class BatteryTrackingIntro extends StatelessWidget {
  const BatteryTrackingIntro({this.registrationEnabled = sunshineBatteryRegistrationEnabled, super.key});
  final bool registrationEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String text(String key) => FlutterI18n.translate(context, 'battery_tracker_$key');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BatteryRegistrationArt(),
        const SizedBox(height: 32),
        Text(text('intro_title'),
            style: theme.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.12)),
        const SizedBox(height: 20),
        Text(text('intro_body'), style: theme.textTheme.bodyLarge?.copyWith(height: 1.6)),
        if (!registrationEnabled) ...[
          const SizedBox(height: 20),
          Text(text('account_unavailable'), style: theme.textTheme.bodyMedium),
        ],
      ],
    );
  }
}

class BatteryRegistrationArt extends StatelessWidget {
  const BatteryRegistrationArt({this.icon = Icons.shield_outlined, this.height = 180, super.key});
  final IconData icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Center(
          child: SizedBox(
            width: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 244,
                  height: height * 0.85,
                  decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
                ),
                Image.asset(
                  'images/battery/batt_full.webp',
                  width: 220,
                  height: height - 12,
                  fit: BoxFit.contain,
                ),
                Positioned(
                  right: 0,
                  bottom: 4,
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 5),
                    ),
                    child: Icon(icon,
                        size: 25, color: colors.primary.computeLuminance() > 0.179 ? Colors.black : Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BatteryFirmwareBadge extends StatelessWidget {
  const BatteryFirmwareBadge({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: FlutterI18n.translate(context, 'battery_tracker_firmware_requirement'),
        child: Text('Librescoot',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
