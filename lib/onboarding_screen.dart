import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/scooter_state.dart';
import 'package:unustasis/scooter_visual.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.service,
    super.key,
  });
  final ScooterService service;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _scanning = false;
  int _step = 0;

  @override
  void initState() {
    widget.service.scanning.listen((scanning) {
      setState(() {
        _scanning = scanning;
      });
    });
    widget.service.connected.listen((connected) {
      if (connected) {
        setState(() {
          _step = 3;
        });
      }
    });
    super.initState();
  }

  List<Widget> getWidgets(int step) {
    switch (step) {
      case 0:
        return [
          Text(
            "Welcome!",
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Text(
            "Unustasis is a third party app for the unu Scooter Pro. Connect your scooter to get started.",
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(
                  60), // fromHeight use double.infinity as width and 40 is the height
            ),
            onPressed: () {
              log("Next");
              setState(() {
                _step = 1;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "LET'S GO",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
            ),
          ),
        ];
      case 1:
        return [
          Text(
            "Connect your scooter",
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Text(
            "Make sure your scooter is turned on and in range. Once you're ready, press the button below to start.",
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(
                  60), // fromHeight use double.infinity as width and 40 is the height
            ),
            onPressed: () {
              log("Next");
              widget.service.start();
              setState(() {
                _step = 2;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "CONNECT",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
            ),
          ),
        ];
      case 2:
        return [
          Text(
            "Scanning...",
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Text(
            "This may take a few seconds. If your phone asks you to pair, please accept and enter the code on your scooter's display.",
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
        ];
      case 3:
        return [
          Text(
            "Success!",
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Text(
            "Your scooter is now connected and ready to use. Press the button below to finish onboarding.",
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(
                  60), // fromHeight use double.infinity as width and 40 is the height
            ),
            onPressed: () {
              log("Next");
              Navigator.of(context).pop();
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                "CONTINUE TO APP",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
            ),
          ),
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 1000),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black,
              _step == 3
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                  : Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ScooterVisual(
                  state: (_step == 0
                      ? ScooterState.standby
                      : (_step == 3
                          ? ScooterState.ready
                          : ScooterState.parked)),
                  scanning: _scanning,
                  blinkerLeft: false,
                  blinkerRight: false,
                ),
              ),
              Column(
                children: [
                  ...getWidgets(_step),
                  const SizedBox(height: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
