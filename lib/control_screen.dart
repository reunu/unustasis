import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import '../home_screen.dart';
import '../scooter_service.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

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
        bottomOpacity: 0.0,
      ),
      body: ListView(
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
                      context.read<ScooterService>().unlock();
                      Navigator.of(context).pop();
                    },
                    icon: Icons.lock_open_outlined,
                    label: FlutterI18n.translate(context, "controls_unlock"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () {
                      context.read<ScooterService>().lock();
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
                      context.read<ScooterService>().wakeUp();
                      Navigator.of(context).pop();
                    },
                    icon: Icons.wb_sunny_outlined,
                    label: FlutterI18n.translate(context, "controls_wake_up"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () {
                      context.read<ScooterService>().hibernate();
                      Navigator.of(context).pop();
                    },
                    icon: Icons.nightlight_outlined,
                    label: FlutterI18n.translate(context, "controls_hibernate"),
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
                    onPressed: () => context
                        .read<ScooterService>()
                        .blink(left: true, right: false),
                    icon: Icons.arrow_back_ios_new_rounded,
                    label:
                        FlutterI18n.translate(context, "controls_blink_left"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: () => context
                        .read<ScooterService>()
                        .blink(left: false, right: true),
                    icon: Icons.arrow_forward_ios_rounded,
                    label:
                        FlutterI18n.translate(context, "controls_blink_right"),
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
                      onPressed: () => context
                          .read<ScooterService>()
                          .blink(left: true, right: true),
                      icon: Icons.code_rounded,
                      label: FlutterI18n.translate(
                          context, "controls_blink_hazard"),
                    ),
                  ),
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: () => context
                          .read<ScooterService>()
                          .blink(left: false, right: false),
                      icon: Icons.code_off_rounded,
                      label:
                          FlutterI18n.translate(context, "controls_blink_off"),
                    ),
                  ),
                ]),
          ),
        ],
      ),
    );
  }
}

class Header extends StatelessWidget {
  const Header(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Text(title,
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7))),
        ),
      ],
    );
  }
}
