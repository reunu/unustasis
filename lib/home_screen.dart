import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:home_widget/home_widget.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helper_widgets/scooter_action_button.dart';
import '../handlebar_warning.dart';
import '../control_screen.dart';
import '../domain/icomoon.dart';
import '../domain/theme_helper.dart';
import '../onboarding_screen.dart';
import '../scooter_service.dart';
import '../domain/scooter_state.dart';
import '../domain/connection_status.dart';
import '../scooter_visual.dart';
import '../stats/stats_screen.dart';
import '../helper_widgets/snowfall.dart';
import '../helper_widgets/grassscape.dart';
import '../command_service.dart';

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

  // Seasonal
  bool _snowing = false;
  bool _forceHover = false;
  bool _spring = false;

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
        // who knows what else might be in the future?
      }
    }
  }

  Future<void> _showOnboardings() async {
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    if (Platform.isAndroid && await prefs.getBool("widgetOnboarded") != true) {
      await showWidgetOnboarding();
      await prefs.setBool("widgetOnboarded", true);
    }
  }

  Future<void> showWidgetOnboarding() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title:
              Text(FlutterI18n.translate(context, "widget_onboarding_title")),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(FlutterI18n.translate(context, "widget_onboarding_body")),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                  FlutterI18n.translate(context, "widget_onboarding_place")),
              onPressed: () async {
                if ((await HomeWidget.isRequestPinWidgetSupported()) == true) {
                  HomeWidget.requestPinWidget(
                    name: 'HomeWidgetReceiver',
                    androidName: 'HomeWidgetReceiver',
                    qualifiedAndroidName:
                        'de.freal.unustasis.HomeWidgetReceiver',
                  );
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(
                  FlutterI18n.translate(context, "widget_onboarding_dismiss")),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
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
                systemNavigationBarColor: Colors.transparent)
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                systemNavigationBarColor: Colors.transparent),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              StateCircle(
                connected: context
                    .select((ScooterService service) => service.connected),
                scooterState:
                    context.select((ScooterService service) => service.state),
                scanning: context
                    .select((ScooterService service) => service.scanning),
              ),
              if (_snowing)
                SnowfallBackground(
                  backgroundColor: Colors.transparent,
                  snowflakeColor: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              if (_spring)
                AnimatedOpacity(
                  opacity: context.watch<ScooterService>().connected == true
                      ? 1.0
                      : 0.0,
                  duration: Duration(milliseconds: 500),
                  child: GrassScape(),
                ),
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
                            builder: (context) => const StatsScreen(),
                          ),
                        ),
                        // Hidden for stable release, but useful for various debugging
                        // onLongPress: () =>
                        //     showHandlebarWarning(didNotUnlock: false),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                                width: context.select(
                                        (ScooterService service) =>
                                            service.connected)
                                    ? 32
                                    : 0),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const StatusText(),
                          const SizedBox(width: 8),
                          const ConnectionStatusText(),
                        ],
                      ),
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
                          const SeatButton(),
                          Selector<ScooterService, ({ScooterState? state, bool lockAvailable, bool unlockAvailable, bool wakeUpAvailable})>(
                              selector: (context, service) => (
                                state: service.state,
                                lockAvailable: service.isCommandAvailableCached(CommandType.lock),
                                unlockAvailable: service.isCommandAvailableCached(CommandType.unlock),
                                wakeUpAvailable: service.isCommandAvailableCached(CommandType.wakeUp),
                              ),
                              builder: (context, data, _) {
                                return Expanded(
                                  child: ScooterPowerButton(
                                      action: data.state != null &&
                                              data.state!.isReadyForLockChange
                                          ? (data.state!.isOn && data.lockAvailable
                                              ? () async {
                                                  try {
                                                    await context
                                                        .read<ScooterService>()
                                                        .lock();
                                                    if (context.mounted &&
                                                        context
                                                            .read<
                                                                ScooterService>()
                                                            .hazardLocking) {
                                                      _flashHazards(1);
                                                    }
                                                  } on SeatOpenException catch (_) {
                                                    log.warning(
                                                        "Seat is open, showing alert");
                                                    showSeatWarning();
                                                  } on HandlebarLockException catch (_) {
                                                    log.warning(
                                                        "Handlebars are still unlocked, showing alert");
                                                    showHandlebarWarning(
                                                      didNotUnlock: false,
                                                    );
                                                  } catch (e, stack) {
                                                    log.severe(
                                                        "Problem opening the seat",
                                                        e,
                                                        stack);
                                                    Fluttertoast.showToast(
                                                        msg: e.toString());
                                                  }
                                                }
                                              : (data.state == ScooterState.standby && data.unlockAvailable
                                                  ? () async {
                                                      try {
                                                        await context
                                                            .read<
                                                                ScooterService>()
                                                            .unlock();
                                                        if (context.mounted &&
                                                            context
                                                                .read<
                                                                    ScooterService>()
                                                                .hazardLocking) {
                                                          _flashHazards(2);
                                                        }
                                                      } on HandlebarLockException catch (_) {
                                                        log.warning(
                                                            "Handlebars are still locked, showing alert");
                                                        showHandlebarWarning(
                                                          didNotUnlock: true,
                                                        );
                                                      }
                                                    }
                                                  : (data.state ==
                                                          ScooterState.standby && data.unlockAvailable
                                                      ? () {
                                                          context
                                                              .read<
                                                                  ScooterService>()
                                                              .unlock();
                                                          // TODO: Flash hazards in visual
                                                        }
                                                      : (data.wakeUpAvailable
                                                          ? context
                                                              .read<
                                                                  ScooterService>()
                                                              .wakeUpAndUnlock
                                                          : null))))
                                          : null,
                                      icon: data.state != null && data.state!.isOn
                                          ? Icons.lock_open
                                          : Icons.lock_outline,
                                      label: data.state != null && data.state!.isOn
                                          ? FlutterI18n.translate(
                                              context, "home_lock_button")
                                          : FlutterI18n.translate(
                                              context, "home_unlock_button")),
                                );
                              }),
                          Selector<ScooterService,
                                  ({bool scanning, bool connected})>(
                              selector: (context, service) => (
                                    scanning: service.scanning,
                                    connected: service.connected
                                  ),
                              builder: (context, state, _) {
                                return Expanded(
                                  child: ScooterActionButton(
                                      onPressed: !state.scanning
                                          ? () {
                                              if (!state.connected) {
                                                log.info(
                                                    "Manually reconnecting...");
                                                try {
                                                  context
                                                      .read<ScooterService>()
                                                      .start();
                                                } catch (e, stack) {
                                                  log.severe(
                                                      "Reconnect button failed",
                                                      e,
                                                      stack);
                                                }
                                              } else {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        const ControlScreen(),
                                                  ),
                                                );
                                              }
                                            }
                                          : null,
                                      icon: !state.connected
                                          ? Icons.refresh_rounded
                                          : Icons.more_vert_rounded,
                                      label: !state.connected
                                          ? FlutterI18n.translate(
                                              context, "home_reconnect_button")
                                          : FlutterI18n.translate(
                                              context, "home_controls_button")),
                                );
                              }),
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

  void showHandlebarWarning({required bool didNotUnlock}) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return HandlebarWarning(
          didNotUnlock: didNotUnlock,
        );
      },
    ).then((dontShowAgain) async {
      if (dontShowAgain == true) {
        Logger("").info("Not showing unlocked handlebar warning again");
        await SharedPreferencesAsync()
            .setBool("unlockedHandlebarsWarning", false);
      }
    });
  }

  void redirectOrStart() async {
    List<String> ids =
        await context.read<ScooterService>().getSavedScooterIds();
    log.info("Saved scooters: $ids");
    if (mounted && ids.isEmpty && !kDebugMode) {
      FlutterNativeSplash.remove();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const OnboardingScreen(),
        ),
      );
    } else {
      // already onboarded, set up and proceed with home page
      _startSeasonal();
      _showOnboardings();
      // start the scooter service if we're not coming from onboarding
      if (mounted && context.read<ScooterService>().myScooter == null) {
        context.read<ScooterService>().start();
      }
    }
    if ((await SharedPreferencesAsync().getBool("biometrics") ?? false) &&
        mounted) {
      context.read<ScooterService>().optionalAuth = false;
      final LocalAuthentication auth = LocalAuthentication();
      try {
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: FlutterI18n.translate(context, "biometrics_message"),
        );
        if (!mounted) return;
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
      if (mounted) context.read<ScooterService>().optionalAuth = true;
    }
  }
}

class SeatButton extends StatelessWidget {
  const SeatButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({bool? seatClosed, ScooterState? state})>(
        selector: (context, service) =>
            (seatClosed: service.seatClosed, state: service.state),
        builder: (context, data, _) {
          return Expanded(
            child: ScooterActionButton(
              onPressed: context.select(
                          (ScooterService service) => service.isCommandAvailableCached(CommandType.openSeat)) &&
                      data.state != null &&
                      data.seatClosed == true &&
                      context.select(
                              (ScooterService service) => service.scanning) ==
                          false &&
                      data.state!.isReadyForSeatOpen == true
                  ? context.read<ScooterService>().openSeat
                  : null,
              label: data.seatClosed == false
                  ? FlutterI18n.translate(context, "home_seat_button_open")
                  : FlutterI18n.translate(context, "home_seat_button_closed"),
              icon: data.seatClosed == false
                  ? Icomoon.seat_open
                  : Icomoon.seat_closed,
              iconColor: data.seatClosed == false
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          );
        });
  }
}

class BatteryBars extends StatelessWidget {
  const BatteryBars({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService,
            ({DateTime? lastPing, int? primarySOC, int? secondarySOC})>(
        selector: (context, service) => (
              lastPing: service.lastPing,
              primarySOC: service.primarySOC,
              secondarySOC: service.secondarySOC
            ),
        builder: (context, data, _) {
          bool dataIsOld = data.lastPing == null ||
              data.lastPing!.difference(DateTime.now()).inMinutes.abs() > 5;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                  width: MediaQuery.of(context).size.width / 6,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.black26,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                    value: data.primarySOC! / 100.0,
                    color: dataIsOld
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4)
                        : data.primarySOC! <= 15
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                  )),
              const SizedBox(width: 8),
              Text("${data.primarySOC}%"),
              if (data.secondarySOC != null && data.secondarySOC! > 0)
                const VerticalDivider(),
              if (data.secondarySOC != null && data.secondarySOC! > 0)
                SizedBox(
                    width: MediaQuery.of(context).size.width / 6,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.black26,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      value: data.secondarySOC! / 100.0,
                      color: dataIsOld
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4)
                          : data.secondarySOC! <= 15
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                    )),
              if (data.secondarySOC != null && data.secondarySOC! > 0)
                const SizedBox(width: 8),
              if (data.secondarySOC != null && data.secondarySOC! > 0)
                Text("${data.secondarySOC}%"),
            ],
          );
        });
  }
}

class StatusText extends StatelessWidget {
  const StatusText({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({ConnectionStatus connectionStatus, ScooterState? scooterState})>(
        selector: (context, service) => (
          connectionStatus: service.connectionStatus,
          scooterState: service.state
        ),
        builder: (context, data, _) {
          String statusText;
          
          // If we have a scooter state, show that; otherwise show connection status
          if (data.scooterState != null) {
            statusText = data.scooterState!.name(context);
          } else {
            // Fallback to connection status
            switch (data.connectionStatus) {
              case ConnectionStatus.none:
                statusText = FlutterI18n.translate(context, "home_loading_state");
                break;
              case ConnectionStatus.ble:
              case ConnectionStatus.cloud:
              case ConnectionStatus.both:
                statusText = FlutterI18n.translate(context, "state_name_unknown");
                break;
              case ConnectionStatus.offline:
                statusText = FlutterI18n.translate(context, "state_name_disconnected");
                break;
            }
          }
          
          return Text(
            statusText,
            style: Theme.of(context).textTheme.titleMedium,
          );
        });
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
                  .withValues(alpha: context.isDarkMode ? 0.5 : 0.7),
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

class _ScooterPowerButtonState extends State<ScooterPowerButton>
    with SingleTickerProviderStateMixin {
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
                            Future.delayed(const Duration(milliseconds: 200),
                                () {
                              setState(() {
                                scale = 1.0; // Return to normal size
                              });
                            });
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    decoration: widget._easterEgg == true
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                width: 2,
                                color: !disabled && widget._easterEgg == true
                                    ? mainColor
                                    : Colors.transparent),
                            image: DecorationImage(
                                image: AssetImage(
                                    "images/decoration/egg_$randomEgg.webp"),
                                fit: BoxFit.cover,
                                opacity: disabled ? 0.3 : 1),
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
                            color: widget._easterEgg == true &&
                                    !context.isDarkMode
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

class ConnectionStatusText extends StatefulWidget {
  const ConnectionStatusText({
    super.key,
  });

  @override
  State<ConnectionStatusText> createState() => _ConnectionStatusTextState();
}

class _ConnectionStatusTextState extends State<ConnectionStatusText>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<ScooterService, ({ConnectionStatus connectionStatus, bool scanning, bool cloudConnecting, ScooterState? state})>(
        selector: (context, service) => (
          connectionStatus: service.connectionStatus,
          scanning: service.scanning,
          cloudConnecting: service.cloudConnecting,
          state: service.state,
        ),
        builder: (context, data, _) {
          final primaryColor = Theme.of(context).colorScheme.primary;
          final disabledColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
          
          bool bleConnected = data.connectionStatus == ConnectionStatus.ble || 
                             data.connectionStatus == ConnectionStatus.both;
          bool cloudConnected = data.connectionStatus == ConnectionStatus.cloud || 
                               data.connectionStatus == ConnectionStatus.both;
          
          // Check if BLE or cloud is connecting
          bool bleConnecting = data.scanning || 
                              data.state == ScooterState.connectingSpecific || 
                              data.state == ScooterState.connectingAuto;
          bool cloudConnecting = data.cloudConnecting;
          
          // Start/stop animation based on connecting states
          bool shouldAnimate = bleConnecting || cloudConnecting;
          if (shouldAnimate && !_animationController.isAnimating) {
            _animationController.repeat(reverse: true);
          } else if (!shouldAnimate && _animationController.isAnimating) {
            _animationController.stop();
            _animationController.reset();
          }
          
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              bleConnecting 
                ? AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Icon(
                        Icons.bluetooth,
                        size: 16,
                        color: bleConnected 
                          ? primaryColor 
                          : disabledColor.withValues(alpha: _pulseAnimation.value),
                      );
                    },
                  )
                : Icon(
                    Icons.bluetooth,
                    size: 16,
                    color: bleConnected ? primaryColor : disabledColor,
                  ),
              const SizedBox(width: 8),
              cloudConnecting 
                ? AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Icon(
                        Icons.cloud,
                        size: 16,
                        color: cloudConnected 
                          ? primaryColor 
                          : disabledColor.withValues(alpha: _pulseAnimation.value),
                      );
                    },
                  )
                : Icon(
                    Icons.cloud,
                    size: 16,
                    color: cloudConnected ? primaryColor : disabledColor,
                  ),
            ],
          );
        });
  }
}
