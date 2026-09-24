// Compatibility exports while callers migrate to core codecs and BLE adapters.
export 'package:scooter_core/characteristic_values.dart' show parseOdometerMeters;
export 'package:scooter_flutter/scooter_flutter.dart'
    show subscribeToStringValue, subscribeToIntValue, subscribeToAlarmWakeSources,
        subscribeToCbbCharging, subscribeToAuxCharging, readOdometer, readNrfVersion;
