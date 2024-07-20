import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/domain/theme_helper.dart';

class ScooterVisual extends StatelessWidget {
  final ScooterState? state;
  final bool scanning;
  final bool blinkerLeft;
  final bool blinkerRight;
  final int? color;

  const ScooterVisual(
      {required this.state,
      required this.scanning,
      required this.blinkerLeft,
      required this.blinkerRight,
      this.color,
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
                      child: Image(
                        image: AssetImage(
                            "images/scooter/base_${color ?? 1}.webp"),
                      ),
                    ),
                    crossFadeState: state == ScooterState.disconnected
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
