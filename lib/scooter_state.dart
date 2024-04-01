import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';

enum ScooterState {
  standby,
  off,
  parked,
  shuttingDown,
  ready,
  hibernating,
  unknown,
  disconnected;

  static ScooterState fromBytes(List<int> bytes) {
    bytes.removeWhere((element) => element == 0);
    String stateString = ascii.decode(bytes).trim();
    switch (stateString) {
      case "stand-by":
        return ScooterState.standby;
      case "off":
        return ScooterState.off;
      case "parked":
        return ScooterState.parked;
      case "shutting-down":
        return ScooterState.shuttingDown;
      case "ready":
        return ScooterState.ready;
      case "hibernating":
        return ScooterState.hibernating;
      default:
        log("Unknown state: $stateString");
        return ScooterState.unknown;
    }
  }
}

extension StateExtension on ScooterState {
  Color get color {
    switch (this) {
      case ScooterState.off:
      case ScooterState.hibernating:
      case ScooterState.shuttingDown:
        // scooter is connected and actionable, but asleep
        return Colors.grey.shade200;
      case ScooterState.ready:
      case ScooterState.parked:
        // scooter is awake and ready to party!
        return Colors.blue;
      case ScooterState.unknown:
      case ScooterState.disconnected:
      default:
        // scooter is disconnected or in a bad state
        return Colors.grey.shade800;
    }
  }

  String get name {
    switch (this) {
      case ScooterState.standby:
        return "Standby";
      case ScooterState.off:
        return "Powered off";
      case ScooterState.parked:
        return "Parked";
      case ScooterState.shuttingDown:
        return "Shutting down";
      case ScooterState.ready:
        return "Ready";
      case ScooterState.hibernating:
        return "Hibernating";
      case ScooterState.unknown:
        return "Unknown state";
      case ScooterState.disconnected:
        return "Disconnected";
    }
  }

  String get description {
    switch (this) {
      case ScooterState.standby:
        return "Shhh! Your scooter is asleep :)";
      case ScooterState.off:
        return "Your scooter is fully powered down";
      case ScooterState.parked:
        return "Your scooter is powered on";
      case ScooterState.shuttingDown:
        return "Your scooter is shutting down...";
      case ScooterState.ready:
        return "Your scooter is driving right now";
      case ScooterState.hibernating:
        return "Your scooter is in hibernation mode";
      case ScooterState.unknown:
        return "Your scooter is currently in a state that this app can't handle";
      case ScooterState.disconnected:
        return "Your scooter is not connected";
    }
  }
}
