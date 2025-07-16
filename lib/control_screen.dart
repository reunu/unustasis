import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import '../helper_widgets/scooter_action_button.dart';
import '../scooter_service.dart';
import '../command_service.dart';

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
      body: Selector<ScooterService, ({
        bool unlockAvailable,
        bool lockAvailable,
        bool wakeUpAvailable,
        bool hibernateAvailable,
        bool blinkerLeftAvailable,
        bool blinkerRightAvailable,
        bool blinkerBothAvailable,
        bool blinkerOffAvailable,
      })>(
        selector: (context, service) => (
          unlockAvailable: service.isCommandAvailableCached(CommandType.unlock),
          lockAvailable: service.isCommandAvailableCached(CommandType.lock),
          wakeUpAvailable: service.isCommandAvailableCached(CommandType.wakeUp),
          hibernateAvailable: service.isCommandAvailableCached(CommandType.hibernate),
          blinkerLeftAvailable: service.isCommandAvailableCached(CommandType.blinkerLeft),
          blinkerRightAvailable: service.isCommandAvailableCached(CommandType.blinkerRight),
          blinkerBothAvailable: service.isCommandAvailableCached(CommandType.blinkerBoth),
          blinkerOffAvailable: service.isCommandAvailableCached(CommandType.blinkerOff),
        ),
        builder: (context, commandAvailability, _) => ListView(
        children: [
          Header(FlutterI18n.translate(context, "controls_state_title")),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: ScooterActionButton(
                    onPressed: commandAvailability.unlockAvailable ? () {
                      context.read<ScooterService>().unlock();
                      Navigator.of(context).pop();
                    } : null,
                    icon: Icons.lock_open_outlined,
                    label: FlutterI18n.translate(context, "controls_unlock"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: commandAvailability.lockAvailable ? () {
                      context.read<ScooterService>().lock();
                      Navigator.of(context).pop();
                    } : null,
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
                    onPressed: commandAvailability.wakeUpAvailable ? () {
                      context.read<ScooterService>().wakeUp();
                      Navigator.of(context).pop();
                    } : null,
                    icon: Icons.wb_sunny_outlined,
                    label: FlutterI18n.translate(context, "controls_wake_up"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: commandAvailability.hibernateAvailable ? () {
                      context.read<ScooterService>().hibernate();
                      Navigator.of(context).pop();
                    } : null,
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
                    onPressed: commandAvailability.blinkerLeftAvailable ? () => context
                        .read<ScooterService>()
                        .blink(left: true, right: false) : null,
                    icon: Icons.arrow_back_ios_new_rounded,
                    label:
                        FlutterI18n.translate(context, "controls_blink_left"),
                  ),
                ),
                Expanded(
                  child: ScooterActionButton(
                    onPressed: commandAvailability.blinkerRightAvailable ? () => context
                        .read<ScooterService>()
                        .blink(left: false, right: true) : null,
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
                      onPressed: commandAvailability.blinkerBothAvailable ? () => context
                          .read<ScooterService>()
                          .blink(left: true, right: true) : null,
                      icon: Icons.code_rounded,
                      label: FlutterI18n.translate(
                          context, "controls_blink_hazard"),
                    ),
                  ),
                  Expanded(
                    child: ScooterActionButton(
                      onPressed: commandAvailability.blinkerOffAvailable ? () => context
                          .read<ScooterService>()
                          .blink(left: false, right: false) : null,
                      icon: Icons.code_off_rounded,
                      label:
                          FlutterI18n.translate(context, "controls_blink_off"),
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

class Header extends StatelessWidget {
  const Header(this.title, {this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7))),
          if (subtitle != null) const SizedBox(height: 2),
          if (subtitle != null)
            Text(subtitle!,
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}
