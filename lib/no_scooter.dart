import 'package:flutter/material.dart';

class NoScooterMsg extends StatelessWidget {
  final bool scanning;
  const NoScooterMsg({this.scanning = false, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          (scanning
              ? const CircularProgressIndicator()
              : const Icon(
                  Icons.sentiment_dissatisfied,
                  size: 48,
                )),
          const SizedBox(height: 32),
          const Text(
            'No Scooter Found',
            style: TextStyle(fontSize: 24),
          ),
          const Text(
            'Please make sure your scooter is turned on and in range.',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}
