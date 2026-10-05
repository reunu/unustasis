# scooter_core

Pure Dart scooter domain logic with no Flutter or plugin imports. The only
runtime dependency is the pure Dart `logging` package.
Import `package:scooter_core/scooter_core.dart` for domain models and the original
protocol/value types. `extended_response.dart` exposes extended-command response
buffering, counted-list parsing, format errors and capability entry parsing.

Extracted behavior includes OTA wire encoding/decoding and release planning,
Go duration conversion, hibernation cron schedules, alarm wake-source parsing,
scooter/vehicle/power/alarm state semantics and extended-response handling.
Implementations and APIs are preserved; the app's legacy domain libraries forward
to these same declarations rather than wrapping or duplicating types.

Transport, BLE plugins, persistence, runtime ownership, widgets, and localization
rendering remain outside this package. Planner warning localization keys and
parameters are temporarily retained for compatibility; presentation resolves them.
Do not add Flutter, plugin, or application-layer dependencies here.

`bluetooth_firmware_updates.dart` exposes
`supportsBluetoothFirmwareUpdates(String? mdbVersion)` for the MDB OS version
(`version:mdb`, exposed as `FirmwareIdentity.imxVersion` over GATT), not DBC or
nRF firmware. Bluetooth OS OTA requires SemVer >=1.2.0 (optional `v` and build
metadata; prereleases of exactly 1.2.0 do not qualify) or a `nightly-`/`testing-`
build dated >=20260803. Dated builds accept `YYYYMMDD` or `YYYYMMDDTHHMMSS` with
valid calendar/time values. Unknown or malformed versions fail closed. Callers
must additionally require a live, non-demo connection and OTA characteristics;
this does not gate USB updates.

Run independently from this directory:

```sh
dart pub get
dart analyze
dart test
```
