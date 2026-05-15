import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../domain/scooter_state.dart';
import '../helper_widgets/header.dart';
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
          // listen to connection state and close if disconnected
          Selector<ScooterService, bool>(
            selector: (context, s) => s.connected,
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
                  onPressed: () {
                    try {
                      context.read<ScooterService>().unlock();
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
                  onPressed: () {
                    try {
                      context.read<ScooterService>().lock();
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
                  onPressed: () {
                    try {
                      context.read<ScooterService>().wakeUp();
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
                  onPressed: () {
                    try {
                      context.read<ScooterService>().hibernate();
                      Navigator.of(context).pop();
                    } catch (e) {
                      Fluttertoast.showToast(msg: e.toString());
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
          SizedBox(height: 64),
        ],
      ),
    );
  }
}
