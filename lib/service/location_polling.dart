import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logging/logging.dart';

final _log = Logger('LocationService');

/// Polls the device's current GPS position.
/// Returns null if location services or permissions are unavailable.
Future<LatLng?> pollLocation() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    _log.warning("Location services are not enabled");
    return null;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      _log.warning("Location permissions are/were denied");
      return null;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    _log.info("Location permissions are denied forever");
    return null;
  }

  Position position = await Geolocator.getCurrentPosition();
  return LatLng(position.latitude, position.longitude);
}
