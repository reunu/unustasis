import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unustasis/scooter_state.dart';

class ScooterVisual extends StatelessWidget {
  final ScooterState state;
  final bool scanning;
  final bool blinkerLeft;
  final bool blinkerRight;

  const ScooterVisual(
      {required this.state, required this.scanning, required this.blinkerLeft, required this.blinkerRight, super.key});

  @override
  Widget build(BuildContext context) {
    var anyBlinker = blinkerLeft || blinkerRight;

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 500),
            firstChild: const Image(
              image: AssetImage("images/scooter/disconnected.png"),
            ),
            secondChild: const Image(
              image: AssetImage("images/scooter/base.png"),
            ),
            crossFadeState: state == ScooterState.disconnected
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
          ),
          AnimatedOpacity(
            opacity: state.isOn ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 1000),
            child: const Image(
              image: AssetImage("images/scooter/light_ring.png"),
            ),
          ),
          AnimatedOpacity(
            opacity: state == ScooterState.ready ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 1000),
            child: const Image(
              image: AssetImage("images/scooter/light_beam.png"),
            ),
          ),
          anyBlinker ? BlinkerWidget(
            blinkerLeft: blinkerLeft,
            blinkerRight: blinkerRight
          ) : SizedBox(),
          // these can even be timed
          CircularProgressIndicator(
            value: scanning || state == ScooterState.shuttingDown ? null : 0.0,
            color: Colors.white,
          ),
        ],
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

  const BlinkerWidget({required this.blinkerLeft, required this.blinkerRight, super.key});

  @override
  _BlinkerWidgetState createState() => _BlinkerWidgetState(blinkerLeft, blinkerRight);
}

class _BlinkerWidgetState extends State<BlinkerWidget> {
  final bool _blinkerLeft;
  final bool _blinkerRight;

  // Variable to track whether to show the image or not
  bool _showBlinker = true;

  // Timer to toggle the image every second
  late Timer _timer;


  _BlinkerWidgetState(this._blinkerLeft, this._blinkerRight);

  @override
  void initState() {
    super.initState();

    // Create a timer that toggles the image every second
    _timer = Timer.periodic(Duration(seconds: 1), (Timer t) {
      // Update the state to toggle the image
      setState(() {
        _showBlinker = !_showBlinker;
      });
    });
  }

  @override
  void dispose() {
    // Cancel the timer to avoid memory leaks
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: _showBlinker && _blinkerLeft ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: const Image(
            image: AssetImage("images/scooter/blinker_l.png"),
          ),
        ),
        AnimatedOpacity(
          opacity: _showBlinker && _blinkerRight ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: const Image(
            image: AssetImage("images/scooter/blinker_r.png"),
          ),
        )
      ]
    );
  }
}