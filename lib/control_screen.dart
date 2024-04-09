import 'package:flutter/material.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/onboarding_screen.dart';
import 'package:unustasis/scooter_service.dart';

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
        title: const Text("Controls"),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ScooterActionButton(
                    onPressed: widget._service.lock,
                    icon: Icons.lock_outline,
                    label: "Lock",
                  ),
                  ScooterActionButton(
                    onPressed: widget._service.unlock,
                    icon: Icons.lock_open_outlined,
                    label: "Unlock",
                  ),
                  ScooterActionButton(
                    onPressed: widget._service.start,
                    icon: Icons.refresh,
                    label: "Refresh",
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
                        widget._service.blink(left: true, right: false),
                    icon: Icons.arrow_back_ios_new_rounded,
                    label: "Blink left",
                  ),
                  ScooterActionButton(
                    onPressed: () =>
                        widget._service.blink(left: true, right: true),
                    icon: Icons.code_rounded,
                    label: "Blink both",
                  ),
                  ScooterActionButton(
                    onPressed: () =>
                        widget._service.blink(left: false, right: true),
                    icon: Icons.arrow_forward_ios_rounded,
                    label: "Blink right",
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
                        widget._service.blink(left: false, right: false),
                    icon: Icons.code_off_rounded,
                    label: "Blinkers off",
                  ),
                  ScooterActionButton(
                    onPressed: () async {
                      showDialog(
                          context: context,
                          barrierDismissible: true,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text("Forget scooter?"),
                              content: const Text(
                                  "To reconnect, you'll need to go though the setup process again."),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(false);
                                  },
                                  child: const Text("Cancel"),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(true);
                                  },
                                  child: const Text("Reset"),
                                ),
                              ],
                            );
                          }).then((reset) {
                        if (reset == true) {
                          widget._service.forgetSavedScooter();
                          Navigator.of(context).pop();
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (context) => OnboardingScreen(
                                service: widget._service,
                              ),
                            ),
                          );
                        }
                      });
                    },
                    icon: Icons.remove_circle_outline,
                    label: "Forget scooter",
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
                        widget._service.wakeUp(),
                    icon: Icons.sunny,
                    label: "Wake up (beta)",
                  ),
                  ScooterActionButton(
                    onPressed: () =>
                        widget._service.hibernate(),
                    icon: Icons.nightlight,
                    label: "Hibernate (beta)",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
