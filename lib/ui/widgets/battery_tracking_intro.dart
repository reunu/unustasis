import 'dart:math' as math;

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

/// Original vector artwork, using the app's colours in either theme.
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(260, height),
              painter: _BatteryPainter(colors.primary, colors.surface, colors.onSurface),
            ),
            Positioned(
              left: null,
              right: math.max(0, (MediaQuery.sizeOf(context).width.clamp(0, 560) - 270) / 2),
              bottom: 12,
              child: Container(
                height: 60,
                width: 60,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 5),
                ),
                child: Icon(icon,
                    size: 27, color: colors.primary.computeLuminance() > 0.179 ? Colors.black : Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.accent, this.surface, this.ink);
  final Color accent;
  final Color surface;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 260, size.height / 180);
    canvas.save();
    canvas.translate((size.width - 260 * scale) / 2, (size.height - 180 * scale) / 2);
    canvas.scale(scale);
    final wash = Paint()..color = accent.withValues(alpha: 0.08);
    canvas.drawOval(const Rect.fromLTWH(18, 18, 224, 150), wash);
    canvas.drawCircle(const Offset(224, 40), 7, Paint()..color = accent.withValues(alpha: 0.2));
    canvas.drawCircle(const Offset(35, 131), 4, Paint()..color = accent.withValues(alpha: 0.35));
    canvas.save();
    canvas.translate(130, 93);
    canvas.rotate(-0.09);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-27, -82, 54, 28), const Radius.circular(10)),
        Paint()..color = ink.withValues(alpha: 0.65));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-16, -75, 32, 16), const Radius.circular(5)),
        Paint()..color = surface);
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(-53, -63, 106, 132), const Radius.circular(18));
    canvas.drawRRect(body.shift(const Offset(4, 5)), Paint()..color = ink.withValues(alpha: 0.06));
    canvas.drawRRect(body, Paint()..color = Color.lerp(surface, ink, 0.08)!);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-53, -36, 106, 42), const Radius.circular(4)),
        Paint()..color = accent.withValues(alpha: 0.8));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-30, 25, 60, 24), const Radius.circular(5)),
        Paint()..color = surface);
    final line = Paint()
      ..color = ink.withValues(alpha: 0.45)
      ..strokeWidth = 2;
    for (var i = 0; i < 9; i++) {
      final x = -21.0 + i * 5;
      canvas.drawLine(Offset(x, 31), Offset(x, i.isEven ? 42 : 38), line);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.surface != surface || oldDelegate.ink != ink;
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
