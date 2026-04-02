import 'package:flutter/material.dart';

class ScooterColor {
  final int value;
  final Color displayColor;
  final String simpleName;

  ScooterColor({
    required this.value,
    required this.displayColor,
    required this.simpleName,
  });
}

final Map<int, ScooterColor> scooterColors = {
  0: ScooterColor(value: 0, displayColor: Colors.black, simpleName: "black"),
  1: ScooterColor(value: 1, displayColor: Colors.white, simpleName: "white"),
  2: ScooterColor(value: 2, displayColor: Colors.green.shade900, simpleName: "green"),
  3: ScooterColor(value: 3, displayColor: Colors.grey, simpleName: "gray"),
  4: ScooterColor(value: 4, displayColor: Colors.deepOrange.shade300, simpleName: "orange"),
  5: ScooterColor(value: 5, displayColor: Colors.red, simpleName: "red"),
  6: ScooterColor(value: 6, displayColor: Colors.blue.shade800, simpleName: "blue"),
  7: ScooterColor(value: 7, displayColor: Colors.grey.shade800, simpleName: "eclipse"),
  8: ScooterColor(value: 8, displayColor: Colors.teal.shade200, simpleName: "idioteque"),
  9: ScooterColor(value: 9, displayColor: Colors.lightBlue, simpleName: "hover"),
};
