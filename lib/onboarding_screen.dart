import 'dart:async';
import 'dart:developer';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:lottie/lottie.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/scooter_visual.dart';
import 'package:unustasis/support_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.service,
    super.key,
  });
  final ScooterService service;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  bool _scanning = false;
  int _step = 0;
  BluetoothDevice? _foundScooter;
  late AnimationController _scanningController;
  late AnimationController _pairingController;
  late StreamSubscription<bool> _scanningSubscription;
  late StreamSubscription<bool> _connectedSubscription;
  // Step 0: Welcome
  // Step 1: Explan visibility
  // Step 2: Scanning (or nothing found, retry)
  // Step 3: Found scooter, explain pairing
  // Step 4: Waiting for pairing
  // Step 5: Connected, all done!

  @override
  void initState() {
    _scanningController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pairingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _pairingController.repeat();
    _scanningSubscription = widget.service.scanning.listen((scanning) {
      if (scanning) {
        _scanningController.repeat();
      } else {
        _scanningController.stop();
      }
      setState(() {
        _scanning = scanning;
      });
    });
    _connectedSubscription = widget.service.connected.listen((connected) {
      if (connected) {
        setState(() {
          _step = 5;
        });
      }
    });
    super.initState();
  }

  List<Widget> getWidgets(int step) {
    switch (step) {
      case 0:
        return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step0_heading"),
            text: FlutterI18n.translate(context, "onboarding_step0_body"),
            btnText: FlutterI18n.translate(context, "onboarding_step0_button"),
            onPressed: () {
              log("Next");
              setState(() {
                _step = 1;
              });
            });
      case 1:
        return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step1_heading"),
            text: FlutterI18n.translate(context, "onboarding_step1_body"),
            btnText: FlutterI18n.translate(context, "onboarding_step1_button"),
            onPressed: () {
              log("Next");
              _startSearch();
              setState(() {
                _step = 2;
              });
            });

      case 2:
        if (_scanning) {
          return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step2_heading"),
            text: FlutterI18n.translate(context, "onboarding_step2_body"),
          );
        } else {
          return _onboardingStep(
              heading: FlutterI18n.translate(
                  context, "onboarding_step2_heading_error"),
              text:
                  FlutterI18n.translate(context, "onboarding_step2_body_error"),
              btnText: FlutterI18n.translate(
                  context, "onboarding_step2_button_error"),
              onPressed: () {
                log("Retrying");
                _startSearch();
              });
        }
      case 3:
        _pairingController.stop();
        return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step3_heading"),
            text: FlutterI18n.translate(context, "onboarding_step3_body",
                translationParams: {
                  "address": _foundScooter!.remoteId.toString()
                }),
            btnText: FlutterI18n.translate(context, "onboarding_step3_button"),
            onPressed: () {
              log("Pairing");
              try {
                widget.service.startWithFoundDevice(device: _foundScooter!);
              } catch (e) {
                log("Error: $e");
                Fluttertoast.showToast(
                    msg: FlutterI18n.translate(
                        context, "onboarding_step4_error"),
                    toastLength: Toast.LENGTH_LONG);
                setState(() {
                  _step = 2;
                });
              }
              setState(() {
                _step = 4;
              });
            });
      case 4:
        _pairingController.repeat();
        return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step4_heading"),
            text: FlutterI18n.translate(context, "onboarding_step4_body"));
      case 5:
        return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step5_heading"),
            text: FlutterI18n.translate(context, "onboarding_step5_body"),
            btnText: FlutterI18n.translate(context, "onboarding_step5_button"),
            onPressed: () {
              log("Continue");
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (context) =>
                    HomeScreen(scooterService: widget.service),
              ));
            });
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const SupportScreen(),
                ));
              },
              icon: const Icon(Icons.help_outline))
        ],
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.15),
            radius: 1,
            colors: [
              _step == 5
                  ? HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                      .withLightness(0.3)
                      .withSaturation(1)
                      .toColor()
                  : Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.onTertiary,
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
              Expanded(child: _onboardingVisual(step: _step)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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

  void _startSearch() async {
    try {
      _foundScooter = await widget.service.findEligibleScooter();
      if (_foundScooter != null) {
        setState(() {
          _step = 3;
        });
      }
    } catch (e) {
      log("Error: $e");
    }
  }

  Widget _onboardingVisual({required int step}) {
    switch (step) {
      case 0:
        int tapCount = 0;
        final tapGestureRecognizer = TapGestureRecognizer()
          ..onTapDown = (_) {
            tapCount++;
            if (tapCount >= 27) {
              // Handle the 10 taps in short succession
              log('27 taps detected! Skipping onboarding...');
              tapCount = 0;
              Navigator.of(context).pushReplacement(MaterialPageRoute(
                builder: (context) => HomeScreen(
                  scooterService: widget.service,
                  forceOpen: true,
                ),
              ));
            }
          };
        return GestureDetector(
          onTapDown: tapGestureRecognizer.onTapDown,
          child: const ScooterVisual(
            state: ScooterState.disconnected,
            scanning: false,
            blinkerLeft: false,
            blinkerRight: false,
          ),
        );

      case 1:
      case 2:
        return Lottie.asset("assets/anim/scanning.json",
            controller: _scanningController);
      case 3:
      case 4:
        return Lottie.asset(
          "assets/anim/found.json",
          controller: _pairingController,
        );
      case 5:
        return const ScooterVisual(
          state: ScooterState.ready,
          scanning: false,
          blinkerLeft: false,
          blinkerRight: false,
        );
      default:
        return const ScooterVisual(
          state: ScooterState.disconnected,
          scanning: false,
          blinkerLeft: false,
          blinkerRight: false,
        );
    }
  }

  List<Widget> _onboardingStep({
    required String heading,
    required String text,
    String? btnText,
    void Function()? onPressed,
  }) {
    return [
      Text(
        heading,
        style: Theme.of(context).textTheme.headlineLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 40),
      if (btnText != null && onPressed != null)
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(
              60,
            ), // fromHeight use double.infinity as width and 40 is the height
            backgroundColor: Theme.of(context).colorScheme.onBackground,
          ),
          onPressed: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              btnText,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onTertiary,
              ),
            ),
          ),
        ),
    ];
  }

  @override
  void dispose() {
    _scanningController.dispose();
    _pairingController.dispose();
    _scanningSubscription.cancel();
    _connectedSubscription.cancel();
    super.dispose();
  }
}
