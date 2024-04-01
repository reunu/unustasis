import 'package:flutter/material.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/scooter_state.dart';
import 'package:unustasis/scooter_visual.dart';

class HomeScreen extends StatefulWidget {
  final ScooterService scooterService;
  const HomeScreen({required this.scooterService, super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ScooterState _scooterState = ScooterState.disconnected;
  bool _connected = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    widget.scooterService.state.listen((state) {
      setState(() {
        _scooterState = state;
      });
    });
    widget.scooterService.connected.listen((isConnected) {
      setState(() {
        _connected = isConnected;
      });
    });
    widget.scooterService.scanning.listen((isScanning) {
      setState(() {
        _scanning = isScanning;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 40,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              Text(
                "unu Scooter Pro",
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              Text(
                _scanning ? "Scanning..." : _scooterState.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Expanded(
                  child: ScooterVisual(
                state: _scooterState,
                scanning: _scanning,
              )),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                mainAxisSize: MainAxisSize.max,
                children: [
                  ElevatedButton.icon(
                    onPressed: _connected ? widget.scooterService.unlock : null,
                    icon: const Icon(Icons.lock_open),
                    label: const Text("Unlock"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _connected ? widget.scooterService.lock : null,
                    icon: const Icon(Icons.lock),
                    label: const Text("Lock"),
                  ),
                  ElevatedButton.icon(
                    onPressed: widget.scooterService.start,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Reset"),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
