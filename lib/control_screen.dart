import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/onboarding_screen.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/stats_screen.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({required ScooterService service, super.key})
      : _service = service;
  final ScooterService _service;

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, "controls_title")),
        elevation: 0.0,
        backgroundColor: Colors.black,
        bottomOpacity: 0.0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Theme.of(context).colorScheme.background,
            ],
          ),
        ),
        child: ListView(
          children: [
            Header(FlutterI18n.translate(context, "controls_state_title")),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ScooterActionButton(
                    onPressed: widget._service.unlock,
                    icon: Icons.lock_open_outlined,
                    label: FlutterI18n.translate(context, "controls_unlock"),
                  ),
                  ScooterActionButton(
                    onPressed: widget._service.lock,
                    icon: Icons.lock_outlined,
                    label: FlutterI18n.translate(context, "controls_lock"),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ScooterActionButton(
                    onPressed: () => widget._service.wakeUp(),
                    icon: Icons.wb_sunny_outlined,
                    label: FlutterI18n.translate(context, "controls_wake_up"),
                  ),
                  ScooterActionButton(
                    onPressed: () => widget._service.hibernate(),
                    icon: Icons.nightlight_outlined,
                    label: FlutterI18n.translate(context, "controls_hibernate"),
                  ),
                ],
              ),
            ),
            Header(FlutterI18n.translate(context, "controls_blinkers_title")),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ScooterActionButton(
                    onPressed: () =>
                        widget._service.blink(left: true, right: false),
                    icon: Icons.arrow_back_ios_new_rounded,
                    label:
                        FlutterI18n.translate(context, "controls_blink_left"),
                  ),
                  ScooterActionButton(
                    onPressed: () =>
                        widget._service.blink(left: false, right: true),
                    icon: Icons.arrow_forward_ios_rounded,
                    label:
                        FlutterI18n.translate(context, "controls_blink_right"),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ScooterActionButton(
                      onPressed: () =>
                          widget._service.blink(left: true, right: true),
                      icon: Icons.code_rounded,
                      label: FlutterI18n.translate(
                          context, "controls_blink_hazard"),
                    ),
                    ScooterActionButton(
                      onPressed: () =>
                          widget._service.blink(left: false, right: false),
                      icon: Icons.code_off_rounded,
                      label:
                          FlutterI18n.translate(context, "controls_blink_off"),
                    ),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}
