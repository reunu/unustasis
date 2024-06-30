import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/interfaces/phone/scooter_action_button.dart';
import 'package:unustasis/interfaces/phone/scooter_power_button.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:wear_plus/wear_plus.dart';

class HomeScreenWatch extends StatefulWidget {
  final ScooterService scooterService;
  final bool? forceOpen;
  const HomeScreenWatch({
    required this.scooterService,
    this.forceOpen,
    super.key,
  });

  @override
  State<HomeScreenWatch> createState() => _HomeScreenStateWatch();
}

class _HomeScreenStateWatch extends State<HomeScreenWatch> {
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
        backgroundColor: Colors.black,
        body: Center(
          child: WatchShape(
            builder: (BuildContext context, WearShape shape, Widget? child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(_scooterState!.name(context), style: TextStyle(color: Colors.white),),
                  ScooterPowerButtonContainer(
                      _scooterState, widget.scooterService),
                  Expanded(
                    child: ScooterActionButton(
                        onPressed: !_scanning
                            ? () {
                          if (!_connected) {
                            widget.scooterService.start();
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
              );
            },
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

  void redirectOrStart() async {
    List<String> ids = await widget.scooterService.getSavedScooterIds();
    log("Saved scooters: $ids");
    if (!(await widget.scooterService.getSavedScooterIds()).isEmpty) {
      // check if we're not coming from onboarding
      if (widget.scooterService.myScooter == null) {
        widget.scooterService.start();
      }
    }
  }
}