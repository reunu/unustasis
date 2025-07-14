import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../domain/scooter_state.dart';
import '../domain/theme_helper.dart';
import '../services/image_cache_service.dart';

class ScooterVisual extends StatelessWidget {
  final ScooterState? state;
  final bool scanning;
  final bool blinkerLeft;
  final bool blinkerRight;
  final int? color;
  final String? colorHex;
  final String? cloudImageUrl;
  final bool hasCustomColor;
  final bool winter;
  final bool aprilFools;

  const ScooterVisual(
      {required this.state,
      required this.scanning,
      required this.blinkerLeft,
      required this.blinkerRight,
      this.winter = false,
      this.aprilFools = false,
      this.color,
      this.colorHex,
      this.cloudImageUrl,
      this.hasCustomColor = false,
      super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.8,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.55,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 500),
                    firstChild: Shimmer.fromColors(
                      baseColor:
                          context.isDarkMode ? Colors.black : Colors.black45,
                      highlightColor: scanning
                          ? Colors.transparent
                          : context.isDarkMode
                              ? Colors.black
                              : Colors.black45,
                      enabled: scanning,
                      direction: ShimmerDirection.ltr,
                      period: const Duration(seconds: 2),
                      child: const Image(
                        image: AssetImage("images/scooter/disconnected.webp"),
                      ),
                    ),
                    secondChild: Opacity(
                      opacity: 1,
                      child: _buildScooterImage(),
                    ),
                    crossFadeState: state == ScooterState.disconnected ||
                            state == ScooterState.connectingAuto
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                  ),
                  if (winter && 
                      state != ScooterState.disconnected && 
                      state != ScooterState.connectingAuto)
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 500),
                      firstChild: const Image(
                        image: AssetImage(
                            "images/scooter/seasonal/winter_on.webp"),
                      ),
                      secondChild: const Image(
                        image: AssetImage(
                            "images/scooter/seasonal/winter_off.webp"),
                      ),
                      crossFadeState: state != null && state!.isOn
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                    ),
                  AnimatedOpacity(
                    opacity: state != null && state!.isOn ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 1000),
                    child: const Image(
                      image: AssetImage("images/scooter/light_ring.webp"),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: state == ScooterState.ready ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 1000),
                    child: const Image(
                      image: AssetImage("images/scooter/light_beam.webp"),
                    ),
                  ),
                ],
              ),
            ),
            //BlinkerWidget(blinkerLeft: blinkerLeft, blinkerRight: blinkerRight),
          ],
        ),
      ),
    );
  }

  /// Builds the main scooter image, handling both local assets and cloud images
  Widget _buildScooterImage() {
    if (hasCustomColor && cloudImageUrl != null) {
      // Use cached cloud image for custom colors - use "front" image for main screen
      return FutureBuilder<File?>(
        future: ImageCacheService().getImage(cloudImageUrl!),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.file(
              snapshot.data!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback to color-based placeholder
                return _buildColorPlaceholder();
              },
            );
          } else if (snapshot.hasError) {
            return _buildColorPlaceholder();
          } else {
            // Loading state - show asset image while loading
            return Image(
              image: AssetImage(
                  "images/scooter/base_${aprilFools ? 9 : color ?? 1}.webp"),
            );
          }
        },
      );
    } else {
      // Use local asset image for predefined colors
      return Image(
        image: AssetImage(
            "images/scooter/base_${aprilFools ? 9 : color ?? 1}.webp"),
      );
    }
  }

  /// Builds a color-based placeholder when cloud image fails to load
  Widget _buildColorPlaceholder() {
    Color effectiveColor = _getEffectiveColor();
    
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: effectiveColor,
          width: 2,
        ),
      ),
      child: Icon(
        Icons.electric_scooter,
        size: 120,
        color: effectiveColor,
      ),
    );
  }

  /// Gets the effective color for display
  Color _getEffectiveColor() {
    if (colorHex != null) {
      // Parse hex color string
      final hexColor = colorHex!.replaceAll('#', '');
      return Color(int.parse('FF$hexColor', radix: 16));
    }
    
    // Return predefined color
    const colorMap = {
      0: Colors.black,
      1: Colors.white,
      2: Colors.green,
      3: Colors.grey,
      4: Colors.deepOrange,
      5: Colors.red,
      6: Colors.blue,
      7: Colors.grey,
      8: Colors.teal,
      9: Colors.lightBlue,
    };
    return colorMap[color ?? 1] ?? Colors.white;
  }

  IconData stateIcon() {
    if (scanning) {
      return Icons.wifi_tethering;
    }
    switch (state) {
      case ScooterState.standby:
        return Icons.power_settings_new;
      case ScooterState.off:
        return Icons.block;
      case ScooterState.parked:
        return Icons.local_parking;
      case ScooterState.shuttingDown:
        return Icons.settings_power;
      case ScooterState.ready:
        return Icons.check_circle;
      case ScooterState.hibernating:
        return Icons.bedtime;
      default:
        return Icons.error;
    }
  }
}

class BlinkerWidget extends StatefulWidget {
  final bool blinkerLeft;
  final bool blinkerRight;

  const BlinkerWidget(
      {required this.blinkerLeft, required this.blinkerRight, super.key});

  @override
  State<BlinkerWidget> createState() => _BlinkerWidgetState();
}

class _BlinkerWidgetState extends State<BlinkerWidget> {
  bool _showBlinker = true;

  // Timer to toggle the image every second
  late Timer _timer;

  @override
  void initState() {
    super.initState();

    var anyBlinker = widget.blinkerLeft || widget.blinkerRight;

    if (anyBlinker) {
      _timer = Timer.periodic(const Duration(milliseconds: 600), (Timer t) {
        setState(() => _showBlinker = !_showBlinker);
      });
    }
  }

  @override
  void dispose() {
    // Cancel the timer to avoid memory leaks
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const blinkerDuration = Duration(milliseconds: 200);

    var showBlinkerLeft = _showBlinker && widget.blinkerLeft;
    var showBlinkerRight = _showBlinker && widget.blinkerRight;

    return Stack(alignment: Alignment.center, children: [
      AnimatedOpacity(
        opacity: showBlinkerLeft ? 1.0 : 0.0,
        duration: blinkerDuration,
        child: const Image(
          image: AssetImage("images/scooter/blinker_l.webp"),
        ),
      ),
      AnimatedOpacity(
        opacity: showBlinkerRight ? 1.0 : 0.0,
        duration: blinkerDuration,
        child: const Image(
          image: AssetImage("images/scooter/blinker_r.webp"),
        ),
      )
    ]);
  }
}
