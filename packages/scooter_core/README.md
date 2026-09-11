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

Run independently from this directory:

```sh
dart pub get
dart analyze
dart test
```
