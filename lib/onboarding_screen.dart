import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
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
            FlutterI18n.translate(context, "onboarding_step0_heading"),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Text(
            FlutterI18n.translate(context, "onboarding_step0_body"),
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
                FlutterI18n.translate(context, "onboarding_step0_button"),
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
            FlutterI18n.translate(context, "onboarding_step1_heading"),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Text(
            FlutterI18n.translate(context, "onboarding_step1_body"),
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
                FlutterI18n.translate(context, "onboarding_step1_button"),
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
            FlutterI18n.translate(context, "onboarding_step2_heading"),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            child: Text(
              FlutterI18n.translate(context, "onboarding_step2_body"),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            onLongPress: () => setState(() {
              _step = 3;
            }),
          ),
          const SizedBox(height: 40),
          !_scanning
              ? ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(
                        60), // fromHeight use double.infinity as width and 40 is the height
                  ),
                  onPressed: () {
                    log("Retrying");
                    widget.service.start();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      FlutterI18n.translate(context, "onboarding_step2_button"),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onBackground,
                      ),
                    ),
                  ),
                )
              : Container(),
        ];
      case 3:
        return [
          Text(
            FlutterI18n.translate(context, "onboarding_step3_heading"),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 16),
          Text(
            FlutterI18n.translate(context, "onboarding_step3_body"),
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
            ),
            onPressed: () {
              log("Next");
              Navigator.of(context).pop();
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                FlutterI18n.translate(context, "onboarding_step3_button"),
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
