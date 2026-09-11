import 'package:latlong2/latlong.dart';
import 'package:scooter_flutter/scooter_telemetry.dart';

/// App presentation metadata layered on the shared firmware state.
class ScooterIdentity extends FirmwareIdentity {
  String? name;
  int? color;
  DateTime? lastPing;
  LatLng? lastLocation;
  int? rssi;
}
