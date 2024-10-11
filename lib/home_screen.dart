import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../control_screen.dart';
import '../domain/icomoon.dart';
import '../domain/theme_helper.dart';
import '../onboarding_screen.dart';
import '../scooter_service.dart';
import '../domain/scooter_state.dart';
import '../scooter_visual.dart';
import '../stats/stats_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool? forceOpen;
  const HomeScreen({
    this.forceOpen,
    super.key,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final log = Logger('HomeScreen');
  bool _hazards = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen != true) {
      log.fine("Redirecting or starting");
      redirectOrStart();
    }
  }

  void _flashHazards(int times) async {
    setState(() {
      _hazards = true;
    });
    await Future.delayed(Duration(milliseconds: 600 * times));
    setState(() {
      _hazards = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final _connected =
        context.select((ScooterService service) => service.connected);
    final _scanning =
        context.select((ScooterService service) => service.scanning);
    final _state = context.select((ScooterService service) => service.state);
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                systemNavigationBarColor: Color.fromARGB(255, 20, 20, 20))
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                systemNavigationBarColor: Colors.white),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              StateCircle(
                  scanning: _scanning,
                  connected: _connected,
                  scooterState: _state),
              SafeArea(
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
                            builder: (context) => StatsScreen(),
                          ),
                        ),
                        // Hidden for stable release
                        // onLongPress: () => Navigator.push(
                        //   context,
                        //   MaterialPageRoute(
                        //     builder: (context) => DrivingScreen(
                        //       service: widget.scooterService,
                        //     ),
                        //   ),
                        // ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: _connected ? 32 : 0),
                            Text(
                              context.select<ScooterService, String?>(
                                      (service) => service.scooterName) ??
                                  FlutterI18n.translate(
                                      context, "stats_no_name"),
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(width: 16),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                      Builder(builder: (context) {
                        return Text(
                          _scanning &&
                                  (_state == null ||
                                      _state == ScooterState.disconnected)
                              ? (context
                                      .read<ScooterService>()
                                      .savedScooters
                                      .isNotEmpty
                                  ? FlutterI18n.translate(
                                      context, "home_scanning_known")
                                  : FlutterI18n.translate(
                                      context, "home_scanning"))
                              : ((_state != null
                                      ? _state.name(context)
                                      : FlutterI18n.translate(
                                          context, "home_loading_state")) +
                                  (_connected &&
                                          context.select<ScooterService, bool?>(
                                                  (service) => service
                                                      .handlebarsLocked) ==
                                              false
                                      ? FlutterI18n.translate(
                                          context, "home_unlocked")
                                      : "")),
                          style: Theme.of(context).textTheme.titleMedium,
                        );
                      }),
                      const SizedBox(height: 16),
                      if (context.select<ScooterService, int?>(
                              (service) => service.primarySOC) !=
                          null)
                        Selector<
                                ScooterService,
                                ({
                                  DateTime? lastPing,
                                  int? primarySOC,
                                  int? secondarySOC
                                })>(
                            selector: (context, service) => (
                                  lastPing: service.lastPing,
                                  primarySOC: service.primarySOC,
                                  secondarySOC: service.secondarySOC
                                ),
                            builder: (context, data, _) {
                              bool dataIsOld = data.lastPing == null ||
                                  data.lastPing!
                                          .difference(DateTime.now())
                                          .inMinutes
                                          .abs() >
                                      5;
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                      width:
                                          MediaQuery.of(context).size.width / 6,
                                      child: LinearProgressIndicator(
                                        minHeight: 8,
                                        borderRadius: BorderRadius.circular(8),
                                        value: data.primarySOC! / 100.0,
                                        color: dataIsOld
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(0.4)
                                            : data.primarySOC! <= 15
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .error
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                      )),
                                  const SizedBox(width: 8),
                                  Text("${data.primarySOC}%"),
                                  if (data.secondarySOC != null &&
                                      data.secondarySOC! > 0)
                                    const VerticalDivider(),
                                  if (data.secondarySOC != null &&
                                      data.secondarySOC! > 0)
                                    SizedBox(
                                        width:
                                            MediaQuery.of(context).size.width /
                                                6,
                                        child: LinearProgressIndicator(
                                          minHeight: 8,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          value: data.secondarySOC! / 100.0,
                                          color: dataIsOld
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                                  .withOpacity(0.4)
                                              : data.secondarySOC! <= 15
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .error
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                        )),
                                  if (data.secondarySOC != null &&
                                      data.secondarySOC! > 0)
                                    const SizedBox(width: 8),
                                  if (data.secondarySOC != null &&
                                      data.secondarySOC! > 0)
                                    Text("${data.secondarySOC}%"),
                                ],
                              );
                            }),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ScooterVisual(
                            color: context.select<ScooterService, int?>(
                                    (service) => service.scooterColor) ??
                                1,
                            state: _state,
                            scanning: _scanning,
                            blinkerLeft: _hazards,
                            blinkerRight: _hazards),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Selector<ScooterService, bool?>(
                              selector: (context, service) =>
                                  service.seatClosed,
                              builder: (context, seatClosed, _) {
                                return Expanded(
                                  child: ScooterActionButton(
                                    onPressed: _connected &&
                                            _state != null &&
                                            seatClosed == true &&
                                            _scanning == false &&
                                            _state.isReadyForSeatOpen == true
                                        ? context
                                            .read<ScooterService>()
                                            .openSeat
                                        : null,
                                    label: seatClosed == false
                                        ? FlutterI18n.translate(
                                            context, "home_seat_button_open")
                                        : FlutterI18n.translate(
                                            context, "home_seat_button_closed"),
                                    icon: seatClosed == false
                                        ? Icomoon.seat_open
                                        : Icomoon.seat_closed,
                                    iconColor: seatClosed == false
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                  ),
                                );
                              }),
                          Expanded(
                            child: ScooterPowerButton(
                                action: _state != null &&
                                        _state.isReadyForLockChange
                                    ? (_state.isOn
                                        ? () {
                                            try {
                                              context
                                                  .read<ScooterService>()
                                                  .lock();
                                              // TODO: Flash hazards in visual
                                            } catch (e, stack) {
                                              if (e
                                                  .toString()
                                                  .contains("SEAT_OPEN")) {
                                                showSeatWarning();
                                              } else {
                                                log.severe(
                                                    "Problem opening the seat",
                                                    e,
                                                    stack);
                                                Fluttertoast.showToast(
                                                    msg: e.toString());
                                              }
                                            }
                                          }
                                        : (_state == ScooterState.standby
                                            ? () {
                                                context
                                                    .read<ScooterService>()
                                                    .unlock();
                                                // TODO: Flash hazards in visual
                                              }
                                            : context
                                                .read<ScooterService>()
                                                .wakeUpAndUnlock))
                                    : null,
                                icon: _state != null && _state.isOn
                                    ? Icons.lock_open
                                    : Icons.lock_outline,
                                label: _state != null && _state.isOn
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
                                          context
                                              .read<ScooterService>()
                                              .start();
                                        } else {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ControlScreen(),
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
            ],
          ),
        ),
      ),
    );
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
    List<String> ids =
        await context.read<ScooterService>().getSavedScooterIds();
    log.info("Saved scooters: $ids");
    if (mounted && ids.isEmpty) {
      FlutterNativeSplash.remove();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const OnboardingScreen(),
        ),
      );
    } else {
      // check if we're not coming from onboarding
      if (mounted && context.read<ScooterService>().myScooter == null) {
        context.read<ScooterService>().start();
      }
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if ((prefs.getBool("biometrics") ?? false) && mounted) {
      context.read<ScooterService>().optionalAuth = false;
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
          context.read<ScooterService>().optionalAuth = true;
        }
      } catch (e, stack) {
        log.info("Biometrics failed", e, stack);
        Fluttertoast.showToast(
            msg: FlutterI18n.translate(context, "biometrics_failed"));
        Navigator.of(context).pop();
        SystemNavigator.pop();
      }
    } else {
      context.read<ScooterService>().optionalAuth = true;
    }
  }
}

class StateCircle extends StatelessWidget {
  const StateCircle({
    super.key,
    required bool scanning,
    required bool connected,
    required ScooterState? scooterState,
  })  : _scanning = scanning,
        _connected = connected,
        _scooterState = scooterState;

  final bool _scanning;
  final bool _connected;
  final ScooterState? _scooterState;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutBack,
      scale: _connected
          ? _scooterState == ScooterState.parked
              ? 1.5
              : (_scooterState == ScooterState.ready)
                  ? 3
                  : 1.2
          : _scanning
              ? 1.5
              : 0,
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: _scooterState?.isOn == true
              ? context.isDarkMode
                  ? HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                      .withLightness(0.18)
                      .toColor()
                  : HSLColor.fromColor(Theme.of(context).colorScheme.primary)
                      .withAlpha(0.3)
                      .toColor()
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainer
                  .withOpacity(context.isDarkMode ? 0.5 : 0.7),
        ),
      ),
    );
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
        : Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(width: 2, color: mainColor),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                backgroundColor:
                    loading ? Theme.of(context).colorScheme.surface : mainColor,
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
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: mainColor,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      widget._icon,
                      color: Theme.of(context).colorScheme.surface,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget._label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: mainColor),
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
            ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2)
            : Theme.of(context).colorScheme.onSurface);
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
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: mainColor),
        ),
      ],
    );
  }
}
