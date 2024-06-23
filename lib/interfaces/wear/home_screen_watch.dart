import 'package:flutter/material.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:wear_plus/wear_plus.dart';

class HomeScreenWatch extends StatelessWidget {
  final ScooterService scooterService;
  final bool? forceOpen;

  const HomeScreenWatch({
    required this.scooterService,
    this.forceOpen,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: WatchShape(
            builder: (BuildContext context, WearShape shape, Widget? child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Shape: ${shape == WearShape.round ? 'round' : 'square'}',
                  ),
                  child!,
                ],
              );
            },
            child: AmbientMode(
              builder: (BuildContext context, WearMode mode, Widget? child) {
                return Text(
                  'Mode: ${mode == WearMode.active ? 'Active' : 'Ambient'}',
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
