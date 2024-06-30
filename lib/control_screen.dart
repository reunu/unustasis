import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:unustasis/interfaces/components/scooter_action_button.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/stats/stats_screen.dart';

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
        backgroundColor: Theme.of(context).colorScheme.onTertiary,
        bottomOpacity: 0.0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.onTertiary,
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () {
                        widget._service.unlock();
                        Navigator.of(context).pop();
                      },
                      icon: Icons.lock_open_outlined,
                      label: FlutterI18n.translate(context, "controls_unlock"),
                    ),
                  ),
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () {
                        widget._service.lock();
                        Navigator.of(context).pop();
                      },
                      icon: Icons.lock_outlined,
                      label: FlutterI18n.translate(context, "controls_lock"),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () {
                        widget._service.wakeUp();
                        Navigator.of(context).pop();
                      },
                      icon: Icons.wb_sunny_outlined,
                      label: FlutterI18n.translate(context, "controls_wake_up"),
                    ),
                  ),
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () {
                        widget._service.hibernate();
                        Navigator.of(context).pop();
                      },
                      icon: Icons.nightlight_outlined,
                      label:
                          FlutterI18n.translate(context, "controls_hibernate"),
                    ),
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
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () =>
                          widget._service.blink(left: true, right: false),
                      icon: Icons.arrow_back_ios_new_rounded,
                      label:
                          FlutterI18n.translate(context, "controls_blink_left"),
                    ),
                  ),
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () =>
                          widget._service.blink(left: false, right: true),
                      icon: Icons.arrow_forward_ios_rounded,
                      label: FlutterI18n.translate(
                          context, "controls_blink_right"),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ScooterActionButton(
                        onPressed: () =>
                            widget._service.blink(left: true, right: true),
                        icon: Icons.code_rounded,
                        label: FlutterI18n.translate(
                            context, "controls_blink_hazard"),
                      ),
                    ),
                    Expanded(
                      child: ScooterActionButton(
                        onPressed: () =>
                            widget._service.blink(left: false, right: false),
                        icon: Icons.code_off_rounded,
                        label: FlutterI18n.translate(
                            context, "controls_blink_off"),
                      ),
                    ),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}
