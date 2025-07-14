import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helper_widgets/leaves.dart';
import '../helper_widgets/scooter_action_button.dart';
import '../helper_widgets/onboarding_popups.dart';
import '../handlebar_warning.dart';
import '../control_screen.dart';
import '../domain/icomoon.dart';
import '../domain/theme_helper.dart';
import '../onboarding_screen.dart';
import '../scooter_service.dart';
import '../domain/scooter_state.dart';
import '../scooter_visual.dart';
import '../battery_screen.dart';
import '../scooter_screen.dart';
import '../settings_screen.dart';
import '../support_screen.dart';
import '../helper_widgets/snowfall.dart';
import '../helper_widgets/clouds.dart';
import '../helper_widgets/grassscape.dart';

class HomeScreen extends StatefulWidget {
  final bool? forceOpen;
  const HomeScreen({this.forceOpen, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final log = Logger('HomeScreen');
  bool _hazards = false;

  // Seasonal
  bool _snowing = false;
  bool _forceHover = false;
  bool _spring = false;
  bool _fall = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen != true) {
      log.fine("Redirecting or starting");
      redirectOrStart();
    }
  }

  Future<void> _startSeasonal() async {
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    if (await prefs.getBool("seasonal") ?? true) {
      switch (DateTime.now().month) {
        case 12:
          // December, snow season!
          setState(() => _snowing = true);
        case 4:
          if (DateTime.now().day == 1) {
            // April fools calls for flying scooters!
            setState(() => _forceHover = true);
          } else {
            // Easter season, place some easter eggs!
            setState(() => _spring = true);
          }
        case 10:
          // October, it's fall by day and halloween by night
          setState(() => _fall = true);
        // who knows what else might be in the future?
      }
    }
  }

  Future<void> _showNotifications() async {
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    if (Platform.isAndroid && await prefs.getBool("widgetOnboarded") != true && mounted) {
      await showWidgetOnboarding(context);
      await prefs.setBool("widgetOnboarded", true);
    }
    if (mounted) await showServerNotifications(context);
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.isDarkMode
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                systemNavigationBarColor: Colors.transparent,
              )
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                systemNavigationBarColor: Colors.transparent,
              ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              StateCircle(
                connected: context.select(
                  (ScooterService service) => service.connected,
                ),
                scooterState: context.select(
                  (ScooterService service) => service.state,
                ),
                scanning: context.select(
                  (ScooterService service) => service.scanning,
                ),
                halloween: _fall && context.isDarkMode,
                fall: _fall && !context.isDarkMode,
              ),
              if (_fall && !context.isDarkMode)
                LeavesBackground(
                  backgroundColor: Colors.transparent,
                  leafColors: const [
                    Color(0xFF8B4000), // brown
                    Color(0xFFFF8C00), // dark orange
                    Color(0xFFFFC107), // amber
                    Color(0xFFB7410E), // russet
                  ],
                  leafCount: 15,
                ),
              if (_snowing)
                SnowfallBackground(
                  backgroundColor: Colors.transparent,
                  snowflakeColor:
                      context.isDarkMode ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
                ),
              if (_fall && context.isDarkMode)
                AnimatedOpacity(
                  opacity: context.watch<ScooterService>().connected == true ? 1.0 : 0.5,
                  duration: Duration(milliseconds: 500),
                  child: Clouds(),
                ),
              if (_spring)
                AnimatedOpacity(
                  opacity: context.watch<ScooterService>().connected == true ? 1.0 : 0.0,
                  duration: Duration(milliseconds: 500),
                  child: GrassScape(),
                ),
              SafeArea(
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 8,
                      child: IconButton(
                        icon: const Icon(Icons.help_outline),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SupportScreen(),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        ),
                      ),
                      const StatusText(),
                      const SizedBox(height: 16),
                      if (context.select<ScooterService, int?>(
                              (service) => service.primarySOC) !=
                          null)
                        const BatteryBars(),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ScooterVisual(
                          color: context.select<ScooterService, int?>(
                                  (service) => service.scooterColor) ??
                              1,
                          colorHex: context.select<ScooterService, String?>(
                                  (service) => service.scooterColorHex),
                          cloudImageUrl: context.select<ScooterService, String?>(
                                  (service) => service.scooterCloudImageUrl),
                          hasCustomColor: context.select<ScooterService, bool>(
                                  (service) => service.scooterHasCustomColor),
                          state: context.select(
                              (ScooterService service) => service.state),
                          scanning: context.select(
                              (ScooterService service) => service.scanning),
                          blinkerLeft: _hazards,
                          blinkerRight: _hazards,
                          winter: _snowing,
                          aprilFools: _forceHover,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ScooterScreen(),
                                  ),
                                ),
                                // Hidden for stable release, but useful for various debugging
                                // onLongPress: () => context.read<ScooterService>().addDemoData(),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: context.select(
                                        (ScooterService service) => service.connected,
                                      )
                                          ? 32
                                          : 0,
                                    ),
                                    Flexible(
                                      child: Text(
                                        context.select<ScooterService, String?>(
                                              (service) => service.scooterName,
                                            ) ??
                                            FlutterI18n.translate(
                                              context,
                                              "stats_no_name",
                                            ),
                                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(height: 1.1),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const StatusText(),
                          if (context.select<ScooterService, String?>(
                                    (service) => service.scooterName,
                                  ) !=
                                  null &&
                              context.select<ScooterService, String?>(
                                    (service) => service.scooterName,
                                  ) !=
                                  FlutterI18n.translate(
                                    context,
                                    "stats_no_name",
                                  ) &&
                              (context.select<ScooterService, int?>(
                                        (service) => service.primarySOC,
                                      ) !=
                                      null ||
                                  context.select<ScooterService, int?>(
                                        (service) => service.secondarySOC,
                                      ) !=
                                      null))
                            Material(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const BatteryScreen(),
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(width: 16),
                                      BatteryBars(
                                        primarySOC: context.select<ScooterService, int?>(
                                          (service) => service.primarySOC,
                                        ),
                                        secondarySOC: context.select<ScooterService, int?>(
                                          (service) => service.secondarySOC,
                                        ),
                                        dataIsOld: context.select<ScooterService, DateTime?>(
                                                  (service) => service.lastPing,
                                                ) ==
                                                null
                                            ? true
                                            : context
                                                    .select<ScooterService, DateTime?>(
                                                      (service) => service.lastPing,
                                                    )!
                                                    .difference(
                                                      DateTime.now(),
                                                    )
                                                    .inMinutes
                                                    .abs() >
                                                5,
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 12,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: ScooterVisual(
                              color: context.select<ScooterService, int?>(
                                    (service) => service.scooterColor,
                                  ) ??
                                  1,
                              state: context.select(
                                (ScooterService service) => service.state,
                              ),
                              scanning: context.select(
                                (ScooterService service) => service.scanning,
                              ),
                              blinkerLeft: _hazards,
                              blinkerRight: _hazards,
                              winter: _snowing,
                              aprilFools: _forceHover,
                              halloween: _fall && context.isDarkMode,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              const SeatButton(),
                              Selector<ScooterService, ScooterState?>(
                                selector: (context, service) => service.state,
                                builder: (context, state, _) {
                                  return Expanded(
                                    child: ScooterPowerButton(
                                      action: state != null && state.isReadyForLockChange
                                          ? (state.isOn
                                              ? () async {
                                                  try {
                                                    await context.read<ScooterService>().lock();
                                                    if (context.mounted &&
                                                        context.read<ScooterService>().hazardLocking) {
                                                      _flashHazards(1);
                                                    }
                                                  } on SeatOpenException catch (_) {
                                                    log.warning(
                                                      "Seat is open, showing alert",
                                                    );
                                                    showSeatWarning();
                                                  } on HandlebarLockException catch (_) {
                                                    log.warning(
                                                      "Handlebars are still unlocked, showing alert",
                                                    );
                                                    showHandlebarWarning(
                                                      didNotUnlock: false,
                                                    );
                                                  } catch (e, stack) {
                                                    log.severe(
                                                      "Problem opening the seat",
                                                      e,
                                                      stack,
                                                    );
                                                    Fluttertoast.showToast(
                                                      msg: e.toString(),
                                                    );
                                                  }
                                                }
                                              : (state == ScooterState.standby
                                                  ? () async {
                                                      try {
                                                        await context.read<ScooterService>().unlock();
                                                        if (context.mounted &&
                                                            context.read<ScooterService>().hazardLocking) {
                                                          _flashHazards(2);
                                                        }
                                                      } on HandlebarLockException catch (_) {
                                                        log.warning(
                                                          "Handlebars are still locked, showing alert",
                                                        );
                                                        showHandlebarWarning(
                                                          didNotUnlock: true,
                                                        );
                                                      }
                                                    }
                                                  : (state == ScooterState.standby
                                                      ? () {
                                                          context.read<ScooterService>().unlock();
                                                          // TODO: Flash hazards in visual
                                                        }
                                                      : context.read<ScooterService>().wakeUpAndUnlock)))
                                          : null,
                                      icon: state != null && state.isOn ? Icons.lock_open : Icons.lock_outline,
                                      label: state != null && state.isOn
                                          ? FlutterI18n.translate(
                                              context,
                                              "home_lock_button",
                                            )
                                          : FlutterI18n.translate(
                                              context,
                                              "home_unlock_button",
                                            ),
                                    ),
                                  );
                                },
                              ),
                              Selector<ScooterService, ({bool scanning, bool connected})>(
                                selector: (context, service) => (
                                  scanning: service.scanning,
                                  connected: service.connected,
                                ),
                                builder: (context, state, _) {
                                  return Expanded(
                                    child: ScooterActionButton(
                                      onPressed: !state.scanning
                                          ? () {
                                              if (!state.connected) {
                                                log.info(
                                                  "Manually reconnecting...",
                                                );
                                                try {
                                                  context.read<ScooterService>().start();
                                                } catch (e, stack) {
                                                  log.severe(
                                                    "Reconnect button failed",
                                                    e,
                                                    stack,
                                                  );
                                                }
                                              } else {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => const ControlScreen(),
                                                  ),
                                                );
                                              }
                                            }
                                          : null,
                                      icon: !state.connected ? Icons.refresh_rounded : Icons.more_vert_rounded,
                                      label: !state.connected
                                          ? FlutterI18n.translate(
                                              context,
                                              "home_reconnect_button",
                                            )
                                          : FlutterI18n.translate(
                                              context,
                                              "home_controls_button",
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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

  void showHandlebarWarning({required bool didNotUnlock}) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return HandlebarWarning(didNotUnlock: didNotUnlock);
      },
    ).then((dontShowAgain) async {
      if (dontShowAgain == true) {
        Logger("").info("Not showing unlocked handlebar warning again");
        await SharedPreferencesAsync().setBool(
          "unlockedHandlebarsWarning",
          false,
        );
      }
    });
  }

  void redirectOrStart() async {
    List<String> ids = await context.read<ScooterService>().getSavedScooterIds();
    log.info("Saved scooters: $ids");
    if (mounted && ids.isEmpty && !kDebugMode) {
      FlutterNativeSplash.remove();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const OnboardingScreen()),
      );
    } else {
      // already onboarded, set up and proceed with home page
      _startSeasonal();
      _showNotifications();
      // start the scooter service if we're not coming from onboarding
      if (mounted && context.read<ScooterService>().myScooter == null) {
        context.read<ScooterService>().start();
      }
    }
    if ((await SharedPreferencesAsync().getBool("biometrics") ?? false) && mounted) {
      context.read<ScooterService>().optionalAuth = false;
      final LocalAuthentication auth = LocalAuthentication();
      try {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: FlutterI18n.translate(context, "biometrics_message"),
        );
        if (!mounted) return;
        if (!didAuthenticate) {
          Fluttertoast.showToast(
            msg: FlutterI18n.translate(context, "biometrics_failed"),
          );
          Navigator.of(context).pop();
          SystemNavigator.pop();
        } else {
          context.read<ScooterService>().optionalAuth = true;
        }
      } catch (e, stack) {
        log.info("Biometrics failed", e, stack);

        Fluttertoast.showToast(
          msg: FlutterI18n.translate(context, "biometrics_failed"),
        );
        Navigator.of(context).pop();

        SystemNavigator.pop();
      }
    } else {
      if (mounted) context.read<ScooterService>().optionalAuth = true;
    }
  }
}

class SeatButton extends StatelessWidget {
  const SeatButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({bool? seatClosed, ScooterState? state})>(
      selector: (context, service) => (seatClosed: service.seatClosed, state: service.state),
      builder: (context, data, _) {
        return Expanded(
          child: ScooterActionButton(
            onPressed: context.select((ScooterService service) => service.connected) &&
                    data.state != null &&
                    data.seatClosed == true &&
                    context.select(
                          (ScooterService service) => service.scanning,
                        ) ==
                        false &&
                    data.state!.isReadyForSeatOpen == true
                ? context.read<ScooterService>().openSeat
                : null,
            label: data.seatClosed == false
                ? FlutterI18n.translate(context, "home_seat_button_open")
                : FlutterI18n.translate(context, "home_seat_button_closed"),
            icon: data.seatClosed == false ? Icomoon.seat_open : Icomoon.seat_closed,
            iconColor: data.seatClosed == false ? Theme.of(context).colorScheme.error : null,
          ),
        );
      },
    );
  }
}

class BatteryBars extends StatelessWidget {
  const BatteryBars({
    required this.primarySOC,
    required this.secondarySOC,
    required this.dataIsOld,
    this.compact = false,
    this.alignment = MainAxisAlignment.center,
    super.key,
  });

  final int? primarySOC;
  final int? secondarySOC;
  final bool? dataIsOld;
  final bool compact;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primarySOC != null) ...[
          SizedBox(
            width: compact ? 40 : MediaQuery.of(context).size.width / 6,
            child: LinearProgressIndicator(
              backgroundColor: Colors.black26,
              minHeight: compact ? 6 : 8,
              borderRadius: BorderRadius.circular(8),
              value: primarySOC! / 100.0,
              color: (dataIsOld ?? true) // if null or true, data is old
                  ? Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4)
                  : primarySOC! <= 15
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "$primarySOC%",
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
        ],
        if (primarySOC != null && secondarySOC != null && secondarySOC! > 0) const VerticalDivider(),
        if (secondarySOC != null && secondarySOC! > 0) ...[
          SizedBox(
            width: compact ? 40 : MediaQuery.of(context).size.width / 6,
            child: LinearProgressIndicator(
              backgroundColor: Colors.black26,
              minHeight: compact ? 6 : 8,
              borderRadius: BorderRadius.circular(8),
              value: secondarySOC! / 100.0,
              color: (dataIsOld ?? true) // if null or true, data is old
                  ? Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4)
                  : secondarySOC! <= 15
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "$secondarySOC%",
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
        ],
      ],
    );
  }
}

class StatusText extends StatelessWidget {
  const StatusText({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({bool connected, bool scanning, ScooterState? state})>(
      selector: (context, service) => (
        state: service.state,
        scanning: service.scanning,
        connected: service.connected,
      ),
      builder: (context, data, _) {
        return Text(
          data.scanning && (data.state == null || data.state == ScooterState.disconnected)
              ? (context.read<ScooterService>().savedScooters.isNotEmpty
                  ? FlutterI18n.translate(context, "home_scanning_known")
                  : FlutterI18n.translate(context, "home_scanning"))
              : ((data.state != null
                      ? data.state!.name(context)
                      : FlutterI18n.translate(
                          context,
                          "home_loading_state",
                        )) +
                  (data.connected &&
                          context.select<ScooterService, bool?>(
                                (service) => service.handlebarsLocked,
                              ) ==
                              false
                      ? FlutterI18n.translate(context, "home_unlocked")
                      : "")),
          style: Theme.of(context).textTheme.titleMedium,
        );
      },
    );
  }
}

class StateCircle extends StatelessWidget {
  const StateCircle({
    super.key,
    required bool scanning,
    required bool connected,
    bool halloween = false,
    bool fall = false,
    required ScooterState? scooterState,
  })  : _scanning = scanning,
        _connected = connected,
        _halloween = halloween,
        _fall = fall,
        _scooterState = scooterState;

  final bool _scanning;
  final bool _connected;
  final bool _halloween;
  final bool _fall;
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
          boxShadow: _halloween && _scooterState?.isOn == true
              ? [
                  BoxShadow(
                    color: Color(0xFFFFCD6F).withAlpha(150),
                    blurRadius: 100,
                    spreadRadius: 10,
                  ),
                ]
              : null,
          image: _halloween
              ? DecorationImage(
                  image: AssetImage("images/decoration/moon.webp"), fit: BoxFit.cover, opacity: _connected ? 0.2 : 0.05)
              : null,
          shape: BoxShape.circle,
          color: _scooterState?.isOn == true
              ? context.isDarkMode
                  ? _halloween
                      ? Color(0xFFFFCD6F).withAlpha(50)
                      : HSLColor.fromColor(
                          Theme.of(context).colorScheme.primary,
                        ).withLightness(0.18).toColor()
                  : _fall
                      ? Color(0xFFFF8400).withAlpha(100)
                      : HSLColor.fromColor(
                          Theme.of(context).colorScheme.primary,
                        ).withAlpha(0.3).toColor()
              : Theme.of(context).colorScheme.surfaceContainer.withValues(
                    alpha: context.isDarkMode ? 0.5 : 0.7,
                  ),
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
    bool? easterEgg,
  })  : _action = action,
        _icon = icon,
        _label = label,
        _easterEgg = easterEgg;

  final void Function()? _action;
  final String _label;
  final IconData _icon;
  final bool? _easterEgg;

  @override
  State<ScooterPowerButton> createState() => _ScooterPowerButtonState();
}

class _ScooterPowerButtonState extends State<ScooterPowerButton> with SingleTickerProviderStateMixin {
  bool loading = false;
  bool disabled = false;
  int? randomEgg = Random().nextInt(8);
  double scale = 1.0;

  @override
  Widget build(BuildContext context) {
    Color mainColor = widget._action == null
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)
        : Theme.of(context).colorScheme.primary;
    disabled = widget._action == null;

    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) {
            if (disabled || loading) return;
            setState(() {
              scale = 0.8; // Shrink the button immediately on tapdown
            });
          },
          onLongPressCancel: () {
            if (disabled || loading) return;
            setState(() {
              scale = 1.0; // Return to full size on cancel
            });
          },
          //onTapUp: (_) {
          //  setState(() {
          //    scale = 1.0; // Return to full size after tapup
          //  });
          //},
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(width: 2, color: mainColor),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    backgroundColor: loading
                        ? Theme.of(context).colorScheme.surface
                        : (widget._easterEgg == true
                            ? disabled
                                ? Colors.white38
                                : Colors.white
                            : mainColor),
                  ),
                  onPressed: disabled
                      ? null
                      : () {
                          Fluttertoast.showToast(msg: widget._label);
                        },
                  onLongPress: disabled
                      ? null
                      : () {
                          setState(() {
                            loading = true;
                          });
                          widget._action!();
                          Future.delayed(const Duration(seconds: 5), () {
                            setState(() {
                              loading = false;
                              scale = 1.1; // Overshoot bounce
                            });
                            Future.delayed(
                              const Duration(milliseconds: 200),
                              () {
                                setState(() {
                                  scale = 1.0; // Return to normal size
                                });
                              },
                            );
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    decoration: widget._easterEgg == true
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: 2,
                              color: !disabled && widget._easterEgg == true ? mainColor : Colors.transparent,
                            ),
                            image: DecorationImage(
                              image: AssetImage(
                                "images/decoration/egg_$randomEgg.webp",
                              ),
                              fit: BoxFit.cover,
                              opacity: disabled ? 0.3 : 1,
                            ),
                          )
                        : null,
                    child: loading
                        ? SizedBox(
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(
                              color: mainColor,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            widget._icon,
                            color: widget._easterEgg == true && !context.isDarkMode
                                ? (disabled ? Colors.black26 : Colors.black87)
                                : Theme.of(context).colorScheme.surface,
                            size: 28,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget._label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: mainColor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
