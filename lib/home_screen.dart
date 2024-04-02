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
  bool _seatClosed = true;
  bool _handlebarsLocked = true;

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
    widget.scooterService.seatClosed.listen((isClosed) {
      setState(() {
        _seatClosed = isClosed;
      });
    });
    widget.scooterService.handlebarsLocked.listen((isLocked) {
      setState(() {
        _handlebarsLocked = isLocked;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        child: SafeArea(
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
                Text(
                  _connected ? (_handlebarsLocked ? "Locked" : "Unlocked") : "",
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
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 24),
                      ),
                      onPressed: _connected && _seatClosed
                          ? widget.scooterService.openSeat
                          : null,
                      icon: const Icon(Icons.work_outline),
                      label: _seatClosed
                          ? const Text("Open Seat")
                          : Text(
                              "Seat is open!",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 24),
                      ),
                      onPressed: _connected
                          ? (_scooterState.isOn
                              ? () {
                                  if (!_seatClosed) {
                                    showSeatWarning();
                                  } else {
                                    widget.scooterService.lock();
                                  }
                                }
                              : widget.scooterService.unlock)
                          : null,
                      icon: Icon(
                          _scooterState.isOn ? Icons.lock : Icons.lock_open),
                      label: Text(_scooterState.isOn ? "Lock" : "Unlock"),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 24),
                      ),
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
      ),
    );
  }

  void showSeatWarning() {
    showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Seat is open!'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                    "For safety reasons, the scooter can't be locked while the seat is open."),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}
