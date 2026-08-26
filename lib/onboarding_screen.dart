import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logging/logging.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:appcheck/appcheck.dart';

import '../domain/scooter_candidate.dart';
import '../domain/scooter_colors.dart';
import '../domain/theme_helper.dart';
import '../helper_widgets/scooter_picker.dart';
import '../home_screen.dart';
import '../scooter_service.dart';
import '../domain/scooter_state.dart';
import '../scooter_visual.dart';
import '../stats/support_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    this.excludedScooterIds,
    this.skipWelcome = false,
    super.key,
  });
  final List<String>? excludedScooterIds;
  final bool skipWelcome;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  final log = Logger('OnboardingScreen');
  int _step = 0;
  ScooterCandidate? _selectedScooter;
  List<ScooterCandidate> _candidates = [];
  StreamSubscription<List<ScooterCandidate>>? _discoverySub;
  bool _searching = false;
  bool? _scanNeedsLocation;
  late AnimationController _scanningController;
  late AnimationController _pairingController;
  int _pendingColor = 0;
  late TextEditingController _nameController;
  // Step 0: Welcome
  // Step 1: Explain visibility
  // Step 2: Scanning, and picking one of the scooters found (or nothing found, retry)
  // Step 4: Waiting for pairing
  // Step 5: Connected, all done!
  // Step 6: Personalize (name + color)

  @override
  void initState() {
    _nameController = TextEditingController(text: "Scooter Pro");
    // for adding second or third scooters
    if (widget.skipWelcome) {
      // show an alert if we discover the old unu app still installed
      _warnOfOldApp();
      // move on in the background
      setState(() {
        _step = 1;
      });
    }
    _scanningController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pairingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _pairingController.repeat();

    context.read<ScooterService>().addListener(() {
      if (mounted) {
        ScooterService service = context.read<ScooterService>();
        if (service.scanning || _searching) {
          _scanningController.repeat();
        } else {
          _scanningController.stop();
        }
        if (service.connected && _step == 4) {
          setState(() {
            _step = 5;
          });
        }
      }
    });

    super.initState();
  }

  void _warnOfOldApp() async {
    final appCheck = AppCheck();
    log.info("Checking for old app");
    bool appInstalled = false;
    if (Platform.isAndroid) {
      appInstalled = await appCheck.isAppInstalled('com.unumotors.app');
    } else if (Platform.isIOS) {
      appInstalled = await appCheck.isAppInstalled('com.unumotors.app://');
    }
    if (appInstalled && mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false, // user must tap button!
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(FlutterI18n.translate(context, "old_app_alert_title")),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(FlutterI18n.translate(context, "old_app_alert_body")),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(FlutterI18n.translate(context, "old_app_alert_acknowledge")),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } else {
      log.info("Old app not detected");
    }
  }

  List<Widget> getWidgets(int step) {
    switch (step) {
      case 0:
        return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step0_heading"),
            text: FlutterI18n.translate(context, "onboarding_step0_body"),
            btnText: FlutterI18n.translate(context, "onboarding_step0_button"),
            onPressed: () {
              // show an alert if we discover the old unu app still installed
              _warnOfOldApp();
              // move on in the background
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
              _startSearch();
              setState(() {
                _step = 2;
              });
            });

      case 2:
        return _pickerStep();
      case 4:
        _pairingController.repeat();
        return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step4_heading"),
            text:
                "${FlutterI18n.translate(context, "onboarding_step4_body")}${Platform.isAndroid ? FlutterI18n.translate(context, "onboarding_step4_explainer") : ""}");
      case 5:
        return _onboardingStep(
            heading: FlutterI18n.translate(context, "onboarding_step5_heading"),
            text: FlutterI18n.translate(context, "onboarding_step5_body"),
            btnText: FlutterI18n.translate(context, "onboarding_step5_button"),
            onPressed: () {
              setState(() {
                _step = 6;
              });
            });
      case 6:
        return _personalizationStep();
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // only show back button if this is not initial onboarding
        automaticallyImplyLeading: widget.skipWelcome ? true : false,
        systemOverlayStyle:
            SystemUiOverlayStyle(statusBarBrightness: context.isDarkMode ? Brightness.dark : Brightness.light),
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
                  : Theme.of(context).colorScheme.surfaceContainer,
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
              Expanded(
                child: Builder(
                  builder: (context) {
                    int tapCount = 0;
                    return GestureDetector(
                      onTap: () {
                        tapCount++;
                        log.info('...visual tapped $tapCount times...');
                        if (tapCount >= 27) {
                          // Handle the 27 taps in short succession
                          log.info('27 taps detected! Skipping onboarding...');
                          tapCount = 0;
                          setState(() {
                            _step = 5;
                          });
                        }
                      },
                      child: _onboardingVisual(step: _step),
                    );
                  },
                ),
              ),
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

  /// Whether a BLE scan on this device still needs location.
  ///
  /// Android 12 dropped that requirement for apps that declare BLUETOOTH_SCAN
  /// with neverForLocation, which this one does, so from API 31 on a scan works
  /// with location permission denied and location services switched off.
  /// Refusing to scan without it locked out anyone who had turned location off.
  /// flutter_blue_plus asks for BLUETOOTH_SCAN and BLUETOOTH_CONNECT itself
  /// when the scan starts, so there is nothing else to request here.
  Future<bool> _scanRequiresLocation() async {
    if (_scanNeedsLocation != null) return _scanNeedsLocation!;
    bool needed = true;
    if (Platform.isAndroid) {
      try {
        final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
        needed = info.version.sdkInt < 31;
      } catch (e, stack) {
        log.warning("Couldn't read the Android version, assuming location is needed", e, stack);
      }
    }
    _scanNeedsLocation = needed;
    return needed;
  }

  Future<bool> _checkAndRequestPermissions() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: FlutterI18n.translate(context, "location_services_disabled"),
          toastLength: Toast.LENGTH_LONG,
        );
      }
      return false;
    }

    // Check location permission (required for Bluetooth scanning before Android 12)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          Fluttertoast.showToast(
            msg: FlutterI18n.translate(context, "location_permission_denied"),
            toastLength: Toast.LENGTH_LONG,
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: FlutterI18n.translate(context, "location_permission_denied_forever"),
          toastLength: Toast.LENGTH_LONG,
        );
      }
      return false;
    }

    return true;
  }

  void _startSearch() async {
    final bool needsLocation = await _scanRequiresLocation();
    if (needsLocation && !await _checkAndRequestPermissions()) {
      log.warning("Permissions not granted, cannot start scanning");
      _stopSearching();
      return;
    }

    if (!mounted) return;

    await _discoverySub?.cancel();
    _discoverySub = null;

    if (!mounted) return;
    setState(() {
      _candidates = [];
      _searching = true;
    });
    _scanningController.repeat();

    _discoverySub = context
        .read<ScooterService>()
        .discoverScooters(
          excludedScooterIds: widget.excludedScooterIds ?? const [],
          androidCheckLocationServices: needsLocation,
        )
        .listen(
          (List<ScooterCandidate> candidates) {
            if (mounted) setState(() => _candidates = candidates);
          },
          onError: (Object e, StackTrace stack) {
            log.severe("Error finding scooters!", e, stack);
            _stopSearching();
          },
          onDone: _stopSearching,
          cancelOnError: true,
        );
  }

  void _stopSearching() {
    if (!mounted) return;
    _scanningController.stop();
    setState(() => _searching = false);
  }

  Future<void> _connectTo(ScooterCandidate candidate) async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    if (!mounted) return;

    final ScooterService service = context.read<ScooterService>();
    _pairingController.reset();
    setState(() {
      _selectedScooter = candidate;
      _searching = false;
      _step = 4;
    });

    try {
      // Awaited on purpose. Firing this off and moving to step 4 anyway left
      // the screen on "Connecting..." forever whenever the attempt failed,
      // because the rejected future never reached the catch below.
      await service.connectToScooterId(candidate.id);
    } catch (e, stack) {
      log.severe("Error connecting to scooter!", e, stack);
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: FlutterI18n.translate(context, "onboarding_step4_error"),
        toastLength: Toast.LENGTH_LONG,
      );
      setState(() {
        _selectedScooter = null;
        _step = 2;
      });
      _startSearch();
    }
  }

  List<Widget> _pickerStep() {
    final bool hasCandidates = _candidates.isNotEmpty;
    final String heading = hasCandidates
        ? FlutterI18n.translate(context, "onboarding_picker_heading")
        : FlutterI18n.translate(context, _searching ? "onboarding_step2_heading" : "onboarding_step2_heading_error");
    final String body = hasCandidates
        ? FlutterI18n.translate(context, "onboarding_picker_body")
        : FlutterI18n.translate(context, _searching ? "onboarding_step2_body" : "onboarding_step2_body_error");

    return [
      Text(
        heading,
        style: Theme.of(context).textTheme.headlineLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      Text(
        body,
        style: Theme.of(context).textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
      if (hasCandidates) ...[
        const SizedBox(height: 24),
        ScooterPicker(
          candidates: _candidates,
          onSelected: _connectTo,
          // the list shares the screen with the animation above it, so cap it
          // by screen height rather than by a number that only fits tall phones
          maxHeight: (MediaQuery.of(context).size.height * 0.32).clamp(140.0, 280.0),
        ),
      ],
      if (hasCandidates && _searching) ...[
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              FlutterI18n.translate(context, "onboarding_picker_still_searching"),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
      if (!_searching) ...[
        const SizedBox(height: 32),
        _primaryButton(
          text: FlutterI18n.translate(
            context,
            hasCandidates ? "onboarding_picker_search_again" : "onboarding_step2_button_error",
          ),
          onPressed: _startSearch,
        ),
      ],
    ];
  }

  Widget _onboardingVisual({required int step}) {
    switch (step) {
      case 0:
        return const ScooterVisual(
          state: ScooterState.disconnected,
          scanning: false,
          blinkerLeft: false,
          blinkerRight: false,
        );
      case 1:
      case 2:
        return Lottie.asset("assets/anim/scanning.json", controller: _scanningController);
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
      case 6:
        return Padding(
          padding: const EdgeInsets.only(top: 40),
          child: ScooterVisual(
            color: _pendingColor,
            state: ScooterState.ready,
            scanning: false,
            blinkerLeft: false,
            blinkerRight: false,
          ),
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

  Widget _colorButton({
    int color = 0,
    Function()? onTap,
    bool selected = false,
  }) {
    return Semantics(
      label: scooterColors[color]!.simpleName,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scooterColors[color]!.displayColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade500, width: 1),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _personalizationStep() {
    return [
      Text(
        FlutterI18n.translate(context, "onboarding_step6_heading"),
        style: Theme.of(context).textTheme.headlineLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      Text(
        FlutterI18n.translate(context, "onboarding_step6_body"),
        style: Theme.of(context).textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      SizedBox(
          height: 48,
          child: ListView.separated(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            itemBuilder: (context, index) {
              return _colorButton(
                color: index,
                selected: _pendingColor == index,
                onTap: () {
                  setState(() {
                    _pendingColor = index;
                  });
                },
              );
            },
            separatorBuilder: (context, index) => const SizedBox(width: 16),
          )),
      SizedBox(height: 32),
      TextField(
        controller: _nameController,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: FlutterI18n.translate(context, "stats_name"),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 40),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          backgroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        onPressed: () {
          final service = context.read<ScooterService>();
          final scooterId = _selectedScooter?.id ?? service.myScooter?.remoteId.toString();
          if (scooterId != null) {
            final name = _nameController.text.trim().isEmpty ? "Scooter Pro" : _nameController.text.trim();
            service.renameSavedScooter(id: scooterId, name: name);
            service.recolorSavedScooter(id: scooterId, color: _pendingColor);
          }
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            FlutterI18n.translate(context, "onboarding_step6_button"),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onTertiary,
            ),
          ),
        ),
      ),
    ];
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
      if (btnText != null && onPressed != null) _primaryButton(text: btnText, onPressed: onPressed),
    ];
  }

  Widget _primaryButton({required String text, required void Function() onPressed}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(
          60,
        ), // fromHeight use double.infinity as width and 40 is the height
        backgroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onTertiary,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _scanningController.dispose();
    _pairingController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
