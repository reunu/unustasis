import 'dart:developer';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/control_screen.dart';
import 'package:unustasis/domain/icomoon.dart';
import 'package:unustasis/domain/theme_helper.dart';
import 'package:unustasis/driving_screen.dart';
import 'package:unustasis/onboarding_screen.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/scooter_visual.dart';
import 'package:unustasis/stats/stats_screen.dart';

class HomeScreen extends StatefulWidget {
  final ScooterService scooterService;
  final bool? forceOpen;
  const HomeScreen({
    required this.scooterService,
    this.forceOpen,
    super.key,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ScooterState? _scooterState = ScooterState.disconnected;
  bool _connected = false;
  bool _scanning = false;
  bool? _seatClosed;
  bool? _handlebarsLocked;
  int? _primarySOC;
  int? _secondarySOC;
  int? color;

  @override
  void initState() {
    super.initState();
    setupColor();
    if (widget.forceOpen != true) {
      log("Redirecting or starting");
      redirectOrStart();
    }
    widget.scooterService.state.listen((state) {
      setState(() {
        _scooterState = state;
      });
    });
    widget.scooterService.connected.listen((isConnected) {
      setState(() {
        _connected = isConnected;
      });
    });
    widget.scooterService.scanning.listen((isScanning) {
      setState(() {
        _scanning = isScanning;
      });
      log("Scanning: $isScanning");
    });
    widget.scooterService.seatClosed.listen((isClosed) {
      setState(() {
        _seatClosed = isClosed;
      });
    });
    widget.scooterService.handlebarsLocked.listen((isLocked) {
      setState(() {
        _handlebarsLocked = isLocked;
      });
    });
    widget.scooterService.primarySOC.listen((soc) {
      setState(() {
        _primarySOC = soc;
      });
    });
    widget.scooterService.secondarySOC.listen((soc) {
      setState(() {
        _secondarySOC = soc;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.3,
              colors: [
                _scooterState?.isOn == true
                    ? HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                        .withLightness(context.isDarkMode ? 0.3 : 0.7)
                        .toColor()
                    : _connected
                        ? HSLColor.fromColor(
                                Theme.of(context).colorScheme.primary)
                            .withLightness(context.isDarkMode ? 0.2 : 0.85)
                            .withSaturation(0.5)
                            .toColor()
                        : Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.onTertiary,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 40,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StatsScreen(
                          service: widget.scooterService,
                        ),
                      ),
                    ),
                    onLongPress: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DrivingScreen(
                          service: widget.scooterService,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: _connected ? 32 : 0),
                        StreamBuilder<String?>(
                            stream: widget.scooterService.scooterName,
                            builder: (context, name) {
                              return Text(
                                name.data ??
                                    FlutterI18n.translate(
                                        context, "stats_no_name"),
                                style:
                                    Theme.of(context).textTheme.headlineLarge,
                              );
                            }),
                        const SizedBox(width: 16),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _scanning &&
                            (_scooterState == null ||
                                _scooterState! == ScooterState.disconnected)
                        ? (widget.scooterService.savedScooters.isNotEmpty
                            ? FlutterI18n.translate(
                                context, "home_scanning_known")
                            : FlutterI18n.translate(context, "home_scanning"))
                        : ((_scooterState != null
                                ? _scooterState!.name(context)
                                : FlutterI18n.translate(
                                    context, "home_loading_state")) +
                            (_connected && _handlebarsLocked == false
                                ? FlutterI18n.translate(
                                    context, "home_unlocked")
                                : "")),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (_primarySOC != null)
                    StreamBuilder<DateTime?>(
                        stream: widget.scooterService.lastPing,
                        builder: (context, lastPing) {
                          bool dataIsOld = !lastPing.hasData ||
                              lastPing.hasData &&
                                  lastPing.data!
                                          .difference(DateTime.now())
                                          .inMinutes
                                          .abs() >
                                      5;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                  width: MediaQuery.of(context).size.width / 6,
                                  child: LinearProgressIndicator(
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(8),
                                    value: _primarySOC! / 100.0,
                                    color: dataIsOld
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.4)
                                        : _primarySOC! < 15
                                            ? Theme.of(context)
                                                .colorScheme
                                                .error
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                  )),
                              const SizedBox(width: 8),
                              Text("$_primarySOC%"),
                              if (_secondarySOC != null && _secondarySOC! > 0)
                                const VerticalDivider(),
                              if (_secondarySOC != null && _secondarySOC! > 0)
                                SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width / 6,
                                    child: LinearProgressIndicator(
                                      minHeight: 8,
                                      borderRadius: BorderRadius.circular(8),
                                      value: _secondarySOC! / 100.0,
                                      color: dataIsOld
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onBackground
                                          : _primarySOC! < 15
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .error
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                    )),
                              if (_secondarySOC != null && _secondarySOC! > 0)
                                const SizedBox(width: 8),
                              if (_secondarySOC != null && _secondarySOC! > 0)
                                Text("$_secondarySOC%"),
                            ],
                          );
                        }),
                  const SizedBox(height: 16),
                  Expanded(
                      child: ScooterVisual(
                          color: color,
                          state: _scooterState,
                          scanning: _scanning,
                          blinkerLeft:
                              false, // TODO: extract ScooterBlinkerState
                          blinkerRight: false)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Expanded(
                        child: ScooterActionButton(
                          onPressed: _connected &&
                                  _scooterState != null &&
                                  _seatClosed == true &&
                                  _scanning == false
                              ? widget.scooterService.openSeat
                              : null,
                          label: _seatClosed == false
                              ? FlutterI18n.translate(
                                  context, "home_seat_button_open")
                              : FlutterI18n.translate(
                                  context, "home_seat_button_closed"),
                          icon: _seatClosed == false
                              ? Icomoon.seat_open
                              : Icomoon.seat_closed,
                          iconColor: _seatClosed == false
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                      Expanded(
                        child: ScooterPowerButton(
                            action: _scooterState != null &&
                                    _scooterState!.isReadyForLockChange
                                ? (_scooterState!.isOn
                                    ? () {
                                        try {
                                          widget.scooterService.lock();
                                        } catch (e) {
                                          if (e
                                              .toString()
                                              .contains("SEAT_OPEN")) {
                                            showSeatWarning();
                                          } else {
                                            Fluttertoast.showToast(
                                                msg: e.toString());
                                          }
                                        }
                                      }
                                    : (_scooterState == ScooterState.standby
                                        ? widget.scooterService.unlock
                                        : widget
                                            .scooterService.wakeUpAndUnlock))
                                : null,
                            icon: _scooterState != null && _scooterState!.isOn
                                ? Icons.lock_open
                                : Icons.lock_outline,
                            label: _scooterState != null && _scooterState!.isOn
                                ? FlutterI18n.translate(
                                    context, "home_lock_button")
                                : FlutterI18n.translate(
                                    context, "home_unlock_button")),
                      ),
                      Expanded(
                        child: ScooterActionButton(
                            onPressed: !_scanning
                                ? () {
                                    if (!_connected) {
                                      widget.scooterService.start();
                                    } else {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ControlScreen(
                                              service: widget.scooterService),
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            icon: (!_connected && !_scanning)
                                ? Icons.refresh_rounded
                                : Icons.more_vert_rounded,
                            label: (!_connected && !_scanning)
                                ? FlutterI18n.translate(
                                    context, "home_reconnect_button")
                                : FlutterI18n.translate(
                                    context, "home_controls_button")),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void setupColor() {
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        color = prefs.getInt("color");
      });
    });
  }

  void showSeatWarning() {
    showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(FlutterI18n.translate(context, "seat_alert_title")),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(FlutterI18n.translate(context, "seat_alert_body")),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void redirectOrStart() async {
    List<String> ids = await widget.scooterService.getSavedScooterIds();
    log("Saved scooters: $ids");
    if ((await widget.scooterService.getSavedScooterIds()).isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OnboardingScreen(
            service: widget.scooterService,
          ),
        ),
      );
    } else {
      // check if we're not coming from onboarding
      if (widget.scooterService.myScooter == null) {
        widget.scooterService.start();
      }
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.getBool("biometrics") ?? false) {
      widget.scooterService.optionalAuth = false;
      final LocalAuthentication auth = LocalAuthentication();
      try {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: FlutterI18n.translate(context, "biometrics_message"),
        );
        if (!didAuthenticate) {
          Fluttertoast.showToast(
              msg: FlutterI18n.translate(context, "biometrics_failed"));
          Navigator.of(context).pop();
          SystemNavigator.pop();
        } else {
          widget.scooterService.optionalAuth = true;
        }
      } catch (e) {
        Fluttertoast.showToast(
            msg: FlutterI18n.translate(context, "biometrics_failed"));
        Navigator.of(context).pop();
        SystemNavigator.pop();
      }
    } else {
      widget.scooterService.optionalAuth = true;
    }
  }
}

class ScooterPowerButton extends StatefulWidget {
  const ScooterPowerButton({
    super.key,
    required void Function()? action,
    Widget? child,
    required IconData icon,
    required String label,
  })  : _action = action,
        _icon = icon,
        _label = label;

  final void Function()? _action;
  final String _label;
  final IconData _icon;

  @override
  State<ScooterPowerButton> createState() => _ScooterPowerButtonState();
}

class _ScooterPowerButtonState extends State<ScooterPowerButton> {
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    Color mainColor = widget._action == null
        ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2)
        : Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            backgroundColor: mainColor,
          ),
          onPressed: () {
            Fluttertoast.showToast(msg: widget._label);
          },
          onLongPress: widget._action == null
              ? null
              : () {
                  setState(() {
                    loading = true;
                  });
                  widget._action!();
                  Future.delayed(const Duration(seconds: 5), () {
                    setState(() {
                      loading = false;
                    });
                  });
                },
          child: loading
              ? SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.background,
                  ),
                )
              : Icon(
                  widget._icon,
                  color: Theme.of(context).colorScheme.background,
                ),
        ),
        const SizedBox(height: 16),
        Text(
          widget._label,
          style: TextStyle(
            color: mainColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class ScooterActionButton extends StatelessWidget {
  const ScooterActionButton({
    super.key,
    required void Function()? onPressed,
    required IconData icon,
    Color? iconColor,
    required String label,
  })  : _onPressed = onPressed,
        _icon = icon,
        _iconColor = iconColor,
        _label = label;

  final void Function()? _onPressed;
  final IconData _icon;
  final String _label;
  final Color? _iconColor;

  @override
  Widget build(BuildContext context) {
    Color mainColor = _iconColor ??
        (_onPressed == null
            ? Theme.of(context).colorScheme.onBackground.withOpacity(0.2)
            : Theme.of(context).colorScheme.onBackground);
    return Column(
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(24),
            side: BorderSide(
              color: mainColor,
            ),
          ),
          onPressed: _onPressed,
          child: Icon(
            _icon,
            color: mainColor,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _label,
          style: TextStyle(
            color: mainColor,
          ),
        ),
      ],
    );
  }
}
