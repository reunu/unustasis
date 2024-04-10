import 'package:flutter/material.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:wakelock/wakelock.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({required ScooterService service, super.key})
      : _service = service;
  final ScooterService _service;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  @override
  void dispose() {
    Wakelock.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Wakelock.enable();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Drive mode"),
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
                children: [
                  ScooterActionButton(
                    onPressed: () =>
                        widget._service.blink(left: true, right: false),
                    icon: Icons.arrow_back_ios_new_rounded,
                    label: "Blink left",
                    size: 48,
                  ),
                  ScooterActionButton(
                    onPressed: () =>
                        widget._service.blink(left: false, right: true),
                    icon: Icons.arrow_forward_ios_rounded,
                    label: "Blink right",
                    size: 48,
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
                      size: 48,
                    ),
                  ]),
            ),
            const SizedBox(height: 32),
            const Divider(color: Colors.grey),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ScooterActionButton(
                      onPressed: () =>
                          widget._service.blink(left: true, right: true),
                      icon: Icons.warning_amber,
                      iconColor: Colors.red,
                      label: "Blink both",
                    ),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}
