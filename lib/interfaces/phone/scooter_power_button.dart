import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/scooter_service.dart';

class ScooterPowerButtonContainer extends StatelessWidget {
  ScooterPowerButtonContainer(this.scooterState, this.scooterService);

  final ScooterState? scooterState;
  final ScooterService scooterService;

  @override
  Widget build(BuildContext context) {
    return ScooterPowerButton(
        action:
            this.scooterState != null && this.scooterState!.isReadyForLockChange
                ? (this.scooterState!.isOn
                    ? () {
                        try {
                          this.scooterService.lock();
                        } catch (e) {
                          if (e.toString().contains("SEAT_OPEN")) {
                            // TODO
                            // showSeatWarning();
                          } else {
                            Fluttertoast.showToast(msg: e.toString());
                          }
                        }
                      }
                    : (this.scooterState == ScooterState.standby
                        ? this.scooterService.unlock
                        : this.scooterService.wakeUpAndUnlock))
                : null,
        icon: this.scooterState != null && this.scooterState!.isOn
            ? Icons.lock_open
            : Icons.lock_outline,
        label: this.scooterState != null && this.scooterState!.isOn
            ? FlutterI18n.translate(context, "home_lock_button")
            : FlutterI18n.translate(context, "home_unlock_button"));
  }
}

class ScooterPowerButton extends StatefulWidget {
  const ScooterPowerButton({
    super.key,
    required void Function()? action,
    Widget? child,
    required IconData icon,
    required String label,
  })  : _action = action,
        _icon = icon,
        _label = label;

  final void Function()? _action;
  final String _label;
  final IconData _icon;

  @override
  State<ScooterPowerButton> createState() => _ScooterPowerButtonState();
}

class _ScooterPowerButtonState extends State<ScooterPowerButton> {
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    Color mainColor = widget._action == null
        ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2)
        : Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            backgroundColor: mainColor,
          ),
          onPressed: () {
            Fluttertoast.showToast(msg: widget._label);
          },
          onLongPress: widget._action == null
              ? null
              : () {
                  setState(() {
                    loading = true;
                  });
                  widget._action!();
                  Future.delayed(const Duration(seconds: 5), () {
                    setState(() {
                      loading = false;
                    });
                  });
                },
          child: loading
              ? SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.background,
                  ),
                )
              : Icon(
                  widget._icon,
                  color: Theme.of(context).colorScheme.background,
                ),
        ),
        const SizedBox(height: 16),
        Text(
          widget._label,
          style: TextStyle(
            color: mainColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
