import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';
import 'package:unustasis/control_screen.dart';
import 'package:unustasis/scooter_service.dart';

enum BlinkerMode { left, right, hazard, off }

class ControlSheet extends StatefulWidget {
  const ControlSheet({super.key});

  @override
  State<ControlSheet> createState() => _ControlSheetState();
}

class _ControlSheetState extends State<ControlSheet> {
  BlinkerMode _blinkerMode = BlinkerMode.off;

  @override
  Widget build(BuildContext context) {
    return BottomSheet(
        showDragHandle: true,
        enableDrag: true,
        onClosing: () {},
        builder: (context) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Header(FlutterI18n.translate(context, "controls_blinkers_title")),
              SegmentedButton<BlinkerMode?>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                style: ButtonStyle(
                  padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
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
                  setState(() {
                    if (value.isNotEmpty) {
                      _blinkerMode = value.first!;
                      context.read<ScooterService>().blink(
                            left: _blinkerMode == BlinkerMode.left || _blinkerMode == BlinkerMode.hazard,
                            right: _blinkerMode == BlinkerMode.right || _blinkerMode == BlinkerMode.hazard,
                          );
                    } else {
                      _blinkerMode = BlinkerMode.off;
                      context.read<ScooterService>().blink(left: false, right: false);
                    }
                  });
                },
              ),
              Header(FlutterI18n.translate(context, "controls_state_title")),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.onSurface,
                        foregroundColor: Theme.of(context).colorScheme.surface,
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        // TODO
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
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () {
                        // TODO
                      },
                      label: Text(FlutterI18n.translate(context, "controls_lock")),
                      icon: const Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 32),
            ],
          );
        });
  }
}
