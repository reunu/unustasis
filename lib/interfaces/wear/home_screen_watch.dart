import 'package:flutter/material.dart';
import 'package:unustasis/scooter_service.dart';

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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text("WEAR"),
      ),
    );
  }
}
