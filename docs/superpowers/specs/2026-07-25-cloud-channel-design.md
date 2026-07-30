# Cloud as a real second channel

Design for the next round of work on `cloud-connectivity` (PR #148), covering the
redundant availability probes, alarm support, navigation over cloud, and the
setup UX gaps Zanooda reported.

## Background

The branch routes commands BLE-first with a cloud fallback, but the two channels
are not peers. Every public method on `ScooterService` hand-rolls its own choice:

```dart
bool viaBLE = _bleReady;
if (viaBLE) {
  await commands.lockScooter(myScooter, characteristicRepository, ...);
} else if (!await _executeCommand(CommandType.lock, context: context)) { ... }
```

`CommandService` is therefore not an abstraction over both channels.
`CloudCommandService` is its only implementation and BLE bypasses it. Three
consequences follow, and this design addresses all of them without replacing the
pattern:

- Nothing owns the channel decision, so availability cannot be cached and gets
  re-probed over the network on every command.
- Nothing owns the cloud channel's lifecycle, so its liveness is incidental to
  whatever the Bluetooth path happens to do.
- Commands that take arguments or return values (navigation) cannot be expressed
  in the `CommandType` enum at all, so `navigation_screen.dart` reaches past the
  abstraction directly into `ble_commands.dart`.

Replacing the per-call-site pattern with a real channel router is the correct end
state, but it touches every command path on a branch that already has an open PR.
It is tracked separately and is not part of this work.

## 1. Command availability and cloud lifecycle

### Probes

`CloudCommandService.isAvailable()` currently ends with two network calls:

```dart
if (!await cloudService.isServiceAvailable()) return false;   // GET /scooters
return await cloudService.isScooterOnline(cloudScooterId);    // GET /scooters/:id
```

`isServiceAvailable()` fetches the entire scooter list and discards the body,
checking only for HTTP 200. `isScooterOnline()` then fetches the single scooter
and reads one boolean. The first call is redundant on its own terms.

It is worse in practice, because `execute()` opens by calling `isAvailable()`
again, and `ScooterService._executeCommand` has already called it. A single honk
issues five requests:

```
_executeCommand()
  isAvailable()        -> GET /scooters + GET /scooters/:id
  [confirmation dialog]
  execute()
    isAvailable()      -> GET /scooters + GET /scooters/:id
    sendCommand()      -> POST /scooters/:id/honk
```

The pre-send check cannot be made correct. The confirmation dialog sits between
the check and the send, so whatever it learned is stale before the POST goes out.
Availability should gate the UI, and the command itself should be the source of
truth for whether it worked.

Changes:

- Delete `CloudService.isServiceAvailable()`.
- `CloudCommandService.isAvailable()` keeps its local guards (command supported in
  cloud, feature flag on, authenticated, a cloud scooter is linked) and then reads
  the cached `ScooterService._isCloudOnline` instead of probing.
- `CloudCommandService.execute()` drops the `isAvailable()` call at its top.
- `isCommandAvailableCached()` is unchanged. It already gates the UI synchronously
  off the same flag.

A honk becomes one request. The cached flag can be up to 30s stale; when it is,
the POST fails and we surface that, which is the outcome the probe-then-pause-
then-send race produced anyway.

### Lifecycle

`ScooterService.start()` waits for the Bluetooth adapter before it does anything
else:

```dart
final adapterStateNow = await flutterBluePlus.adapterState.first;
if (adapterStateNow != BluetoothAdapterState.on) {
  await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
}
```

`_maybeRefreshCloudStatus()` sits below that. With the adapter off, the await
never completes and the cloud check never runs. Every foreground entry point goes
through `start()` (`scooter_service.dart:148`, `home_screen.dart:515`, `:606`);
only the background service uses `attemptLatestAutoConnection()`, which does call
the cloud check first. So in the app itself, cloud is gated behind Bluetooth being
on, which defeats the feature.

Change: move the cleanup block and `_maybeRefreshCloudStatus()` above the adapter
gate, so the order becomes cleanup, cloud refresh, wait for Bluetooth, scan. The
30s poll then starts and keeps running with the adapter off.

Both must move together. Cleanup sets `connected = false` and
`state = disconnected`, and `_refreshCloudOnlineStatus` only writes state when
`_isCloudOnline && !connected`. Moving the refresh alone would let the later
cleanup stomp the state the refresh just set.

## 2. Alarm

Sunshine exposes `alarm_arm`, `alarm_disarm` and `alarm_stop` alongside the
`alarm` command the branch already sends. There is no BLE equivalent for any of
them, so they extend an existing pattern rather than adding a new one:
`CommandType.alarm` already returns false from `_bleSupportsCommand`.

Changes:

- Three new `CommandType` values: `alarmArm`, `alarmDisarm`, `alarmStop`, mapped
  to `POST /scooters/:id/alarm_arm` / `alarm_disarm` / `alarm_stop`, cloud-only,
  supported in `CloudCommandService`, false in `_bleSupportsCommand`.
- `_refreshCloudOnlineStatus()` reads `alarm_state` and `alarm_triggered` off the
  payload it already fetches and stores them on `ScooterService`. No new polling.
- The control sheet's existing cloud actions block (the "alerts" header,
  `_CloudActionButton`, `isCommandAvailableCached` gating) gains an alarm state
  line and the relevant action.

Sunshine's seven `alarm_state` values map onto the available action:

| `alarm_state` | action offered |
| --- | --- |
| `armed`, `delay-armed` | disarm |
| `disarmed`, `seatbox-access` | arm |
| `level-1-triggered`, `level-2-triggered` | stop |
| `disabled` | none |

Alarm settings (duration, hairtrigger, seatbox-trigger) stay out of scope.
Sunshine has no API route for them; they exist only in its web UI.

## 3. Navigation over cloud

`PUT /scooters/:id/destination` and `DELETE /scooters/:id/destination` map onto
`navigateCommand` and `cancelNavigationCommand`. Both take `scooter_control`
scope and return the `{status: "success"}` envelope the command endpoints use.

Changes:

- `CloudService.setDestination(scooterId, lat, lng, {name})` and
  `CloudService.clearDestination(scooterId)`.
- `_navigateToDestination` and `_navigateToFav` in `navigation_screen.dart` both
  funnel into one helper on `ScooterService` taking a `NavDestination`, which
  picks a channel: BLE if `_bleReady`, else cloud if
  `currentScooter?.cloudScooterId != null && _isCloudOnline`, else queue via
  `setPendingNavigation`.
- `cancelNavigationCommand` gets the same treatment against `DELETE`.

The favourite id stays on the BLE branch only, where `navigateFavCommand` can use
it. Below that branch everything travels as coordinates plus name.

This is already how the code degrades today: `_navigateToFav` falls back to
`setPendingNavigation(destination)` when disconnected, and
`_dispatchPendingNavigation` sends it through `navigateCommand` with coordinates
and name rather than the favourite id. Cloud slots into the same place.
`_pendingNavigation` survives as the last resort when neither channel is up, but
stops being the normal path for a scooter out of Bluetooth range.

Favourites are not reconciled with sunshine's `saved_destinations`. The two
systems grew independently, and since the scooter has no concept of users, the
only common denominator is the destination data itself. `nav:fav:add`,
`nav:fav:navigate`, `nav:fav:delete` and the `_cachedDestinations` mirror are
untouched, and `saved_destinations` is not consumed.

## 4. Cloud setup UX

Two gaps from Zanooda's review of PR #148.

### Authentication state is not observable

`CloudSettingsSection` caches `_isAuthenticated` in local state, populated in
`initState` and `didChangeDependencies`. The OAuth callback lands in
`main.dart:155`, which calls `handleOAuthCallback` and only logs the result.
Nothing notifies the settings section, and `didChangeDependencies` does not fire
on resume from an external browser, so the tile keeps offering "Connect to cloud"
until the widget tree is rebuilt from scratch.

Change: `ScooterService` already owns the cached cloud flags the UI watches
(`_isCloudOnline`, `_isCloudConnecting`), so `_isCloudAuthenticated` joins them.
It is set at init and after the OAuth callback, with `notifyListeners()`.
`main.dart`'s deep-link handler routes through `ScooterService` rather than
reaching into `cloudService` directly, and `CloudSettingsSection` drops its local
cache for a `Selector`. No new `ChangeNotifier`.

### Linking is not discoverable

The link control lives in the per-scooter detail screen
(`scooter_screen.dart:646`), behind the feature flag, and only says "Not linked to
cloud" once you navigate there. Nothing tells the user that authenticating is half
the setup, so a signed-in user with Bluetooth off sees "disconnected" with no
explanation.

Change: `CloudSettingsSection` gains a row, shown only once authenticated, giving
the link state of `ScooterService.currentScooter`, falling back to
`getMostRecentScooter()` when none is connected, with an action that opens the
scooter screen where the linking control lives. That
is the same resolution `navigation_screen._getCurrentSavedScooter` uses. The row
is hidden when the user has no saved scooters at all. The per-scooter control
stays where it is. This is a second entry point at the moment the user is
thinking about cloud setup, not a move.

## Testing

`scooterStateFromCloudData` established the pattern on this branch: pure functions
over payload maps, tested without plugins. The same applies to the new logic:

- `alarmActionFor(alarmState)`, deciding which action a given state offers, and
  `alarmStateI18nKey(alarmState)` for its label.
- `navChannelFor(bleReady:, cloudLinked:, cloudOnline:)`, choosing the channel a
  navigation destination travels over.

The HTTP methods on `CloudService` stay untested, consistent with the rest of the
file.

The availability change in section 1 gets no unit test. It is a refactor whose
only observable effect is fewer requests, and nothing in `CloudService` takes an
injectable HTTP client, so there is no seam to assert against without building
one. It is verified by the existing suite staying green and by reading the
request log once, which the plan spells out as a manual step.

## Out of scope

- `play_sound`. Vestigial.
- Trips, events, log bundles, and the wider `telemetry` block.
- Alarm settings, which have no API route.
- Reconciling favourites with `saved_destinations`.
- The `ScooterChannel` refactor that would replace per-call-site branching with a
  router. Tracked separately.
- PR #148 review item 4 (seatbox and controls staying disabled after connect).
  Fixed by PR #153, still open; the branch picks it up on the next merge of main.
