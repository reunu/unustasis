import 'package:flutter/material.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/scooter_service.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({required ScooterService scooterService, super.key})
      : _scooterService = scooterService;
  final ScooterService _scooterService;

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
                children: [
                  ScooterActionButton(
                    onPressed: widget._scooterService.lock,
                    icon: Icons.lock_outline,
                    label: "Lock",
                  ),
                  ScooterActionButton(
                    onPressed: widget._scooterService.unlock,
                    icon: Icons.lock_open_outlined,
                    label: "Unlock",
                  ),
                  ScooterActionButton(
                    onPressed: widget._scooterService.start,
                    icon: Icons.refresh,
                    label: "Refresh",
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
