import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../command_service.dart';
import '../domain/connection_status.dart';
import '../domain/scooter_state.dart';
import '../features.dart';
import '../helper_widgets/header.dart';
import '../hibernate_sheet.dart';
import '../scooter_service.dart';

enum BlinkerMode { left, right, hazard, off }

class ControlSheet extends StatefulWidget {
  const ControlSheet({super.key});

  @override
  State<ControlSheet> createState() => _ControlSheetState();
}

class _ControlSheetState extends State<ControlSheet> with TickerProviderStateMixin {
  BlinkerMode _blinkerMode = BlinkerMode.off;
  bool _disconnectedHandled = false;

  Future<bool> _confirmHardReboot(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(FlutterI18n.translate(context, "controls_hard_reboot_confirm_title")),
            content: Text(FlutterI18n.translate(context, "controls_hard_reboot_confirm_message")),
            actions: [
              TextButton(
                child: Text(FlutterI18n.translate(context, "cancel")),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.onSurface,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(FlutterI18n.translate(context, "controls_hard_reboot_confirm_button")),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // listen to connection state and close if disconnected, via BLE or cloud
          Selector<ScooterService, bool>(
            selector: (context, s) => s.connected || s.connectionStatus.isConnected,
            shouldRebuild: (prev, next) => !_disconnectedHandled && prev != next,
            builder: (context, connected, _) {
              if (!connected && !_disconnectedHandled) {
                _disconnectedHandled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _blinkerMode = BlinkerMode.off;
                  });
                  Navigator.of(context).pop();
                });
              }
              return const SizedBox.shrink();
            },
          ),
          Center(
              child: Header(
            FlutterI18n.translate(context, "controls_blinkers_title"),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          )),
          SegmentedButton<BlinkerMode?>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            style: ButtonStyle(
              padding: WidgetStatePropertyAll<EdgeInsets>(
                const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            segments: const [
              ButtonSegment<BlinkerMode?>(
                value: BlinkerMode.left,
                icon: Icon(Icons.chevron_left_rounded, size: 24),
              ),
              ButtonSegment<BlinkerMode?>(
                value: BlinkerMode.hazard,
                icon: Icon(Icons.warning_amber_rounded, size: 24),
              ),
              ButtonSegment<BlinkerMode?>(
                value: BlinkerMode.right,
                icon: Icon(Icons.chevron_right_rounded, size: 24),
              ),
            ],
            selected: {_blinkerMode},
            onSelectionChanged: (value) {
              if (value.isNotEmpty) {
                try {
                  context.read<ScooterService>().blink(
                        left: value.first == BlinkerMode.left || value.first == BlinkerMode.hazard,
                        right: value.first == BlinkerMode.right || value.first == BlinkerMode.hazard,
                      );
                  setState(() {
                    _blinkerMode = value.first!;
                  });
                } catch (e) {
                  Fluttertoast.showToast(msg: e.toString());
                }
              } else {
                try {
                  context.read<ScooterService>().blink(left: false, right: false);
                  setState(() {
                    _blinkerMode = BlinkerMode.off;
                  });
                } catch (e) {
                  Fluttertoast.showToast(msg: e.toString());
                }
              }
            },
          ),
          Center(child: Header(FlutterI18n.translate(context, "controls_state_title"))),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    try {
                      await context.read<ScooterService>().unlock(context: context);
                    } catch (e) {
                      Fluttertoast.showToast(msg: e.toString());
                    }
                  },
                  label: Text(FlutterI18n.translate(context, "controls_unlock")),
                  icon: const Icon(Icons.lock_open_outlined),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    try {
                      await context.read<ScooterService>().lock(context: context);
                    } catch (e) {
                      Fluttertoast.showToast(msg: e.toString());
                    }
                  },
                  label: Text(FlutterI18n.translate(context, "controls_lock")),
                  icon: const Icon(Icons.lock_outline_rounded),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    try {
                      await context.read<ScooterService>().wakeUp(context: context);
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    } catch (e) {
                      Fluttertoast.showToast(msg: e.toString());
                    }
                  },
                  label: Text(FlutterI18n.translate(context, "controls_wake_up")),
                  icon: const Icon(Icons.power_settings_new_rounded),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    final service = context.read<ScooterService>();
                    if (service.identity.supportsHibernateFor == true) {
                      final done = await showModalBottomSheet<bool>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (context) => const HibernateSheet(),
                      );
                      if (!context.mounted) return;
                      // also close if the scooter disconnected while the sheet
                      // was open: the disconnect listener above will have
                      // popped the sheet instead of this control sheet
                      if (done == true || !(service.connected || service.connectionStatus.isConnected)) {
                        Navigator.of(context).pop();
                      }
                    } else {
                      try {
                        await service.hibernate(context: context);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      } catch (e) {
                        Fluttertoast.showToast(msg: e.toString());
                      }
                    }
                  },
                  label: Text(FlutterI18n.translate(context, "controls_hibernate")),
                  icon: const Icon(Icons.nightlight_outlined),
                ),
              ),
            ],
          ),
          Selector<ScooterService, bool>(
            selector: (context, s) => s.identity.isLibrescoot == true,
            builder: (context, isLibrescoot, _) {
              if (!isLibrescoot) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  Selector<ScooterService, bool>(
                    selector: (context, s) => s.state?.permitsHardReboot == true,
                    builder: (context, permitsHardReboot, _) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.onSurface,
                                foregroundColor: Theme.of(context).colorScheme.surface,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () async {
                                try {
                                  await context.read<ScooterService>().reboot();
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                } catch (e) {
                                  Fluttertoast.showToast(msg: e.toString());
                                }
                              },
                              label: Text(FlutterI18n.translate(context, "controls_reboot")),
                              icon: const Icon(Icons.restart_alt_rounded),
                            ),
                          ),
                          if (permitsHardReboot) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  backgroundColor: Theme.of(context).colorScheme.onSurface,
                                  foregroundColor: Theme.of(context).colorScheme.surface,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                onPressed: () async {
                                  final confirmed = await _confirmHardReboot(context);
                                  if (!mounted) return;
                                  if (!confirmed) return;
                                  try {
                                    if (!context.mounted) return;
                                    await context.read<ScooterService>().hardReboot();
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                  } catch (e) {
                                    Fluttertoast.showToast(msg: e.toString());
                                  }
                                },
                                label: Text(FlutterI18n.translate(context, "controls_hard_reboot")),
                                icon: const Icon(Icons.warning_amber_rounded),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
          FutureBuilder<bool>(
            future: Features.isCloudConnectivityEnabled,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return Selector<ScooterService, Map<CommandType, bool>>(
                selector: (context, s) => {
                  for (final c in const [
                    CommandType.locate,
                    CommandType.honk,
                    CommandType.alarm,
                    CommandType.ping,
                    CommandType.getState,
                  ])
                    c: s.isCommandAvailableCached(c),
                },
                builder: (context, available, _) {
                  if (!available.values.any((v) => v)) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      Center(child: Header(FlutterI18n.translate(context, "controls_alerts_title"))),
                      Row(
                        children: [
                          if (available[CommandType.locate] == true)
                            Expanded(
                              child: _CloudActionButton(
                                labelKey: "controls_locate",
                                icon: Icons.location_searching_rounded,
                                onPressed: (context) => context.read<ScooterService>().locate(context: context),
                              ),
                            ),
                          if (available[CommandType.locate] == true && available[CommandType.honk] == true)
                            const SizedBox(width: 16),
                          if (available[CommandType.honk] == true)
                            Expanded(
                              child: _CloudActionButton(
                                labelKey: "cloud_command_honk",
                                icon: Icons.campaign_outlined,
                                onPressed: (context) => context.read<ScooterService>().honk(context: context),
                              ),
                            ),
                        ],
                      ),
                      if (available[CommandType.alarm] == true) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _CloudActionButton(
                                labelKey: "cloud_command_alarm",
                                icon: Icons.notifications_active_outlined,
                                onPressed: (context) => context.read<ScooterService>().alarm(context: context),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (available[CommandType.ping] == true || available[CommandType.getState] == true) ...[
                        const SizedBox(height: 16),
                        Center(child: Header(FlutterI18n.translate(context, "controls_diagnostics_title"))),
                        Row(
                          children: [
                            if (available[CommandType.ping] == true)
                              Expanded(
                                child: _CloudActionButton(
                                  labelKey: "controls_ping",
                                  icon: Icons.network_ping_outlined,
                                  onPressed: (context) => context.read<ScooterService>().pingScooter(context: context),
                                ),
                              ),
                            if (available[CommandType.ping] == true && available[CommandType.getState] == true)
                              const SizedBox(width: 16),
                            if (available[CommandType.getState] == true)
                              Expanded(
                                child: _CloudActionButton(
                                  labelKey: "controls_get_state",
                                  icon: Icons.info_outline_rounded,
                                  onPressed: (context) => context.read<ScooterService>().getState(context: context),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
          SizedBox(height: 64),
        ],
      ),
    );
  }
}

/// A cloud-only control button, styled to match the rest of the sheet.
class _CloudActionButton extends StatelessWidget {
  final String labelKey;
  final IconData icon;
  final Future<void> Function(BuildContext context) onPressed;

  const _CloudActionButton({
    required this.labelKey,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.onSurface,
        foregroundColor: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      onPressed: () async {
        try {
          await onPressed(context);
        } catch (e) {
          Fluttertoast.showToast(msg: e.toString());
        }
      },
      label: Text(FlutterI18n.translate(context, labelKey)),
      icon: Icon(icon),
    );
  }
}
