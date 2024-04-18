import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:unustasis/scooter_service.dart';

class DrivingScreen extends StatefulWidget {
  final ScooterService service;
  const DrivingScreen({required this.service, super.key});

  @override
  State<DrivingScreen> createState() => _DrivingScreenState();
}

class _DrivingScreenState extends State<DrivingScreen> {
  int _speed = 0;

  @override
  void initState() {
    startLocator();
    super.initState();
  }

  void startLocator() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw "Location services are not enabled";
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw "Location permissions are/were denied";
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw "Location permissions are denied forever";
    }

    Geolocator.getPositionStream().listen((Position position) {
      if (position.speedAccuracy < 3) {
        setState(() {
          _speed = (position.speed * 3.6).round();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driving'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: RotatedBox(
                    quarterTurns: -1,
                    child: CircularProgressIndicator(
                      value: _speed / 120,
                      strokeWidth: 10,
                      backgroundColor: Colors.grey.shade800,
                    ),
                  ),
                ),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(_speed.toString(),
                          style: const TextStyle(
                              fontSize: 64, fontStyle: FontStyle.italic)),
                      const Text(" km/h", style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            StreamBuilder(
              stream: widget.service.primarySOC,
              builder: (context, snapshot) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${(snapshot.data ?? 0).toString()}%'),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 150,
                      child: LinearProgressIndicator(
                        value: (snapshot.data ?? 0) / 100,
                        backgroundColor: Colors.grey.shade800,
                        color: Colors.blue,
                        minHeight: 16,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    )
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder(
              stream: widget.service.secondarySOC,
              builder: (context, snapshot) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${(snapshot.data ?? 0).toString()}%'),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 150,
                      child: LinearProgressIndicator(
                        value: (snapshot.data ?? 0) / 100,
                        backgroundColor: Colors.grey.shade800,
                        color: Colors.blue,
                        minHeight: 16,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    )
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
