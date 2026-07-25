# Cloud as a Real Second Channel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the cloud usable as a peer to Bluetooth on the `cloud-connectivity` branch: stop the redundant availability probes, stop gating the cloud behind the Bluetooth adapter, add alarm arm/disarm/stop, route navigation over cloud, and close the two setup UX gaps from the PR #148 review.

**Architecture:** Keep the existing per-call-site `viaBLE ? ble : cloud` pattern that `ScooterService.lock()` uses. Push decision logic into pure functions under `lib/domain/` so it is testable without plugins, and keep `CloudService` as the thin HTTP layer. No channel-router refactor: that is tracked separately.

**Tech Stack:** Flutter, Dart, `http`, `provider`, `flutter_i18n`, `flutter_blue_plus`, `flutter_test`.

## Global Constraints

- Work happens on branch `cloud-connectivity` in the worktree `/home/teal/src/reunu/unustasis-cloud`.
- NEVER use em-dashes or en-dashes anywhere, including code comments, commit messages, and doc text. Use a plain hyphen, a comma, parentheses, or split the sentence.
- Conventional commits style. Do not mention Claude or Claude Code in commit messages.
- `git commit` takes explicit file paths. Never `git add .`.
- Every i18n key added must be added to all five locale files: `assets/i18n/en.json`, `de.json`, `fr.json`, `nl.json`, `pi.json`. `pi` is Pirate English; match its register (existing examples: `"controls_alerts_title": "Alarums"`, `"cloud_command_alarm": "Sound the alarm"`).
- Line length is 120 columns (`analysis_options.yaml`).
- `flutter analyze` must report only the 2 pre-existing infos in `lib/service/ble_commands.dart:489`. Any new issue is a failure.
- Run `flutter test` before every commit. It must stay green.
- Sunshine base URL is `https://sunshine.rescoot.org/api/v1`, already in `CloudService._baseUrl`.

---

## File Structure

**Create:**
- `lib/domain/alarm_state.dart` - pure mapping from sunshine's `alarm_state` string to the action the UI should offer.
- `lib/domain/nav_channel.dart` - pure choice of navigation channel given BLE and cloud readiness.
- `test/domain/alarm_state_test.dart`
- `test/domain/nav_channel_test.dart`

**Modify:**
- `lib/cloud_service.dart` - delete `isServiceAvailable()`, add alarm and destination HTTP methods.
- `lib/cloud_command_service.dart` - `isAvailable()` reads cached state, `execute()` drops its duplicate check, alarm commands become supported.
- `lib/command_service.dart` - three new `CommandType` values.
- `lib/scooter_service.dart` - cloud lifecycle above the Bluetooth gate, alarm state fields, alarm command methods, navigation channel helper, `_isCloudAuthenticated`.
- `lib/main.dart` - OAuth deep link routes through `ScooterService`.
- `lib/control_sheet.dart` - alarm state line and action button.
- `lib/stats/cloud_settings_section.dart` - watch auth state, add the linking row.
- `assets/i18n/{en,de,fr,nl,pi}.json` - new keys.
- `docs/superpowers/specs/2026-07-25-cloud-channel-design.md` - one correction, see Task 9.

---

### Task 1: Stop probing the network for command availability

`CloudCommandService.isAvailable()` calls `cloudService.isServiceAvailable()` (a `GET /scooters` whose body is discarded) and then `cloudService.isScooterOnline()` (a `GET /scooters/:id` that reads one boolean). `execute()` then calls `isAvailable()` again, and `ScooterService._executeCommand` has already called it. A honk costs five requests.

`ScooterService` already maintains `_isCloudOnline`, refreshed every 30s by `_refreshCloudOnlineStatus()`, exposed as `isCloudOnline`. `isAvailable()` should read that.

This task is a refactor with no new behaviour to unit test. There is no HTTP injection seam anywhere in `CloudService`, so the request-count change is verified by reading the log, not by a test. The existing suite must stay green.

**Files:**
- Modify: `lib/cloud_service.dart` (delete `isServiceAvailable()`)
- Modify: `lib/cloud_command_service.dart` (`isAvailable()`, `execute()`)

**Interfaces:**
- Consumes: `ScooterService.isCloudOnline` (existing `bool` getter).
- Produces: `CloudCommandService` constructor gains a third positional parameter `bool Function() isCloudOnline`. Task 4 relies on this constructor shape.

- [ ] **Step 1: Delete `isServiceAvailable()` from `CloudService`**

Remove this whole method from `lib/cloud_service.dart`:

```dart
  // Check if cloud service is available
  Future<bool> isServiceAvailable() async {
    if (!await isAuthenticated) {
      return false;
    }

    try {
      // Use the scooters endpoint to check service availability
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/scooters'),
        headers: headers,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
```

- [ ] **Step 2: Give `CloudCommandService` access to the cached flag**

In `lib/cloud_command_service.dart`, change the fields and constructor:

```dart
class CloudCommandService implements CommandService {
  final CloudService cloudService;
  final Future<int?> Function() getCurrentCloudScooterId;
  final bool Function() isCloudOnline;
  final log = Logger('CloudCommandService');

  CloudCommandService(this.cloudService, this.getCurrentCloudScooterId, this.isCloudOnline);
```

- [ ] **Step 3: Replace the probes in `isAvailable()`**

Replace the body of `isAvailable()` with:

```dart
  @override
  Future<bool> isAvailable(CommandType command) async {
    // Guards are ordered cheapest first and short-circuit deliberately:
    // cloudService.isAuthenticated can trigger a token refresh, so it must not
    // run when the feature is off or the command has no cloud equivalent.
    if (!_isCommandSupportedInCloud(command)) {
      return false;
    }
    if (!await Features.isCloudConnectivityEnabled) {
      return false;
    }
    if (!await cloudService.isAuthenticated) {
      return false;
    }
    if (await getCurrentCloudScooterId() == null) {
      return false;
    }
    // Read the flag the 30s poll maintains rather than probing. Availability
    // gates the UI; the command's own response says whether it landed.
    return isCloudOnline();
  }
```

- [ ] **Step 4: Drop the duplicate check in `execute()`**

In `execute()`, replace:

```dart
  Future<bool> execute(CommandType command) async {
    if (!await isAvailable(command)) {
      log.warning('Cloud command $command not available');
      return false;
    }

    final cloudScooterId = await getCurrentCloudScooterId();
```

with:

```dart
  Future<bool> execute(CommandType command) async {
    // Callers check isAvailable() first. Re-checking here bought nothing: the
    // confirmation dialog sits between the check and the send, so the answer is
    // stale by the time the request goes out either way.
    final cloudScooterId = await getCurrentCloudScooterId();
```

- [ ] **Step 5: Update the construction site**

In `lib/scooter_service.dart`, `_ensureCloudServicesInitialized()`, change:

```dart
    _cloudCommandService = CloudCommandService(_cloudService!, () async => currentScooter?.cloudScooterId);
```

to:

```dart
    _cloudCommandService = CloudCommandService(
      _cloudService!,
      () async => currentScooter?.cloudScooterId,
      () => _isCloudOnline,
    );
```

- [ ] **Step 6: Verify**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter analyze`
Expected: `2 issues found` (the two pre-existing `unintended_html_in_doc_comment` infos).

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 7: Manual verification of the request count**

Build and run the app on a device with a cloud-linked scooter, cloud connectivity enabled, and Bluetooth off. Fire a honk from the control sheet. In the log, `CloudService` should log exactly one request for the command (the `POST`), with no `Getting cloud scooters from` line triggered by the command itself. The 30s poll's `GET /scooters/:id` is expected and separate.

- [ ] **Step 8: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git commit lib/cloud_service.dart lib/cloud_command_service.dart lib/scooter_service.dart -m "perf(cloud): read cached online state instead of probing per command

isAvailable() fetched the whole scooter list to check for HTTP 200, then
fetched the single scooter to read one boolean, and execute() ran the same
check again on top of the caller's. A honk cost five requests.

The pre-send check was never sound anyway: the confirmation dialog sits
between it and the send. Availability gates the UI off the flag the 30s
poll already maintains, and the command's own response is what says
whether it landed."
```

---

### Task 2: Refresh cloud status without waiting for Bluetooth

`ScooterService.start()` awaits the Bluetooth adapter turning on before it reaches `_maybeRefreshCloudStatus()`. With the adapter off the await never completes, so the cloud is never checked. Every foreground entry point goes through `start()` (`scooter_service.dart:148`, `home_screen.dart:515`, `home_screen.dart:606`).

The cleanup block must move with the refresh. Cleanup sets `connected = false` and `state = disconnected`; `_refreshCloudOnlineStatus` only writes state when `_isCloudOnline && !connected`. Moving the refresh alone would let the later cleanup stomp what the refresh just set.

Not unit testable: `start()` needs a live `flutter_blue_plus` adapter. Verified manually.

**Files:**
- Modify: `lib/scooter_service.dart` (`start()`)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new.

- [ ] **Step 1: Reorder `start()`**

In `lib/scooter_service.dart`, `start()` currently reads:

```dart
    // If Bluetooth is already on, don't wait for another "on" transition event.
    final BluetoothAdapterState adapterStateNow = await flutterBluePlus.adapterState.first;
    if (adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
    }

    // CLEANUP
    _foundSth = false;
    connected = false;
    state = ScooterState.disconnected;
    if (myScooter != null) {
      myScooter!.disconnect();
    }

    // Check cloud reachability for cloud-linked scooters alongside the BLE scan below,
    // never blocking on it.
    _maybeRefreshCloudStatus();

    // SCAN
```

Replace that whole run with:

```dart
    // CLEANUP
    _foundSth = false;
    connected = false;
    state = ScooterState.disconnected;
    if (myScooter != null) {
      myScooter!.disconnect();
    }

    // Cloud reachability does not depend on the Bluetooth adapter, and it is the
    // only channel left when the adapter is off, so check it before waiting on
    // one. Cleanup has to stay above this: it clears `connected`, which
    // _refreshCloudOnlineStatus reads before it writes state.
    _maybeRefreshCloudStatus();

    // If Bluetooth is already on, don't wait for another "on" transition event.
    final BluetoothAdapterState adapterStateNow = await flutterBluePlus.adapterState.first;
    if (adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
    }

    // SCAN
```

- [ ] **Step 2: Verify**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter analyze`
Expected: `2 issues found`.

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 3: Manual verification**

With a cloud-linked scooter, cloud connectivity enabled, and Bluetooth turned **off** on the phone, cold-start the app. Expected: the home screen shows the scooter as cloud-connected within a few seconds, and the log shows `ScooterService` calling `_refreshCloudOnlineStatus` without any adapter-state wait. Before this change it stayed disconnected indefinitely.

- [ ] **Step 4: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git commit lib/scooter_service.dart -m "fix(cloud): check cloud reachability before waiting on the BT adapter

start() awaited the Bluetooth adapter turning on before it got anywhere
near the cloud check, so with Bluetooth off the cloud was never contacted.
Every foreground entry point goes through start(), which made cloud
connectivity strictly conditional on Bluetooth being available.

Reported by Zanooda on #148."
```

---

### Task 3: Alarm state to UI action, as a pure function

Sunshine's serializer exposes `alarm_state` with seven values. The control sheet needs to know which of arm, disarm or stop to offer.

**Files:**
- Create: `lib/domain/alarm_state.dart`
- Test: `test/domain/alarm_state_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum AlarmAction { arm, disarm, stop }`, `AlarmAction? alarmActionFor(String? alarmState)`, and `String alarmStateI18nKey(String? alarmState)`. Tasks 5 and 6 rely on all three.

- [ ] **Step 1: Write the failing test**

Create `test/domain/alarm_state_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/alarm_state.dart';

void main() {
  group('alarmActionFor', () {
    test('an armed alarm offers disarm', () {
      expect(alarmActionFor('armed'), AlarmAction.disarm);
      expect(alarmActionFor('delay-armed'), AlarmAction.disarm);
    });

    test('a disarmed alarm offers arm', () {
      expect(alarmActionFor('disarmed'), AlarmAction.arm);
      expect(alarmActionFor('seatbox-access'), AlarmAction.arm);
    });

    test('a triggered alarm offers stop', () {
      expect(alarmActionFor('level-1-triggered'), AlarmAction.stop);
      expect(alarmActionFor('level-2-triggered'), AlarmAction.stop);
    });

    test('a disabled or unknown alarm offers nothing', () {
      expect(alarmActionFor('disabled'), isNull);
      expect(alarmActionFor(null), isNull);
      expect(alarmActionFor('something-new'), isNull);
    });
  });

  group('alarmStateI18nKey', () {
    test('maps every known state to its own key', () {
      const states = [
        'armed',
        'delay-armed',
        'disarmed',
        'seatbox-access',
        'level-1-triggered',
        'level-2-triggered',
        'disabled',
      ];
      final keys = states.map(alarmStateI18nKey).toSet();
      expect(keys.length, states.length, reason: 'each state needs a distinct key');
      expect(keys.every((k) => k.startsWith('alarm_state_')), isTrue);
    });

    test('falls back to unknown', () {
      expect(alarmStateI18nKey(null), 'alarm_state_unknown');
      expect(alarmStateI18nKey('something-new'), 'alarm_state_unknown');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter test test/domain/alarm_state_test.dart`
Expected: FAIL, `Error: Couldn't resolve the package 'unustasis' ... alarm_state.dart` or `Target of URI doesn't exist`.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/alarm_state.dart`:

```dart
/// The alarm action a given state should offer the user.
enum AlarmAction { arm, disarm, stop }

/// Maps sunshine's `alarm_state` onto the single action worth offering.
///
/// Returns null for `disabled` (the alarm system is off, nothing to do from
/// here) and for anything sunshine grows later that we don't recognise.
AlarmAction? alarmActionFor(String? alarmState) {
  switch (alarmState) {
    case 'armed':
    case 'delay-armed':
      return AlarmAction.disarm;
    case 'disarmed':
    case 'seatbox-access':
      return AlarmAction.arm;
    case 'level-1-triggered':
    case 'level-2-triggered':
      return AlarmAction.stop;
    default:
      return null;
  }
}

/// i18n key naming the alarm state for display.
String alarmStateI18nKey(String? alarmState) {
  switch (alarmState) {
    case 'armed':
      return 'alarm_state_armed';
    case 'delay-armed':
      return 'alarm_state_delay_armed';
    case 'disarmed':
      return 'alarm_state_disarmed';
    case 'seatbox-access':
      return 'alarm_state_seatbox_access';
    case 'level-1-triggered':
      return 'alarm_state_triggered_l1';
    case 'level-2-triggered':
      return 'alarm_state_triggered_l2';
    case 'disabled':
      return 'alarm_state_disabled';
    default:
      return 'alarm_state_unknown';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/alarm_state_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git add lib/domain/alarm_state.dart test/domain/alarm_state_test.dart
git commit lib/domain/alarm_state.dart test/domain/alarm_state_test.dart -m "feat(cloud): map sunshine alarm states onto UI actions"
```

---

### Task 4: Alarm commands over cloud

Sunshine exposes `POST /scooters/:id/alarm_arm`, `alarm_disarm` and `alarm_stop`. There is no BLE equivalent, so these join `CommandType.alarm` as cloud-only. `CloudService.sendCommand` already takes a command path segment, so no new HTTP method is needed.

**Files:**
- Modify: `lib/command_service.dart`
- Modify: `lib/cloud_command_service.dart`
- Modify: `lib/scooter_service.dart`

**Interfaces:**
- Consumes: `CloudCommandService` constructor from Task 1.
- Produces: `CommandType.alarmArm`, `CommandType.alarmDisarm`, `CommandType.alarmStop`; `ScooterService.alarmArm({BuildContext? context})`, `alarmDisarm({BuildContext? context})`, `alarmStop({BuildContext? context})`, all `Future<void>` and all throwing on failure. Task 6 calls these.

- [ ] **Step 1: Add the enum values**

In `lib/command_service.dart`, extend `CommandType`:

```dart
enum CommandType {
  lock,
  unlock,
  wakeUp,
  hibernate,
  openSeat,
  blinkerLeft,
  blinkerRight,
  blinkerBoth,
  blinkerOff,
  honk,
  alarm,
  alarmArm,
  alarmDisarm,
  alarmStop,
  locate,
  ping,
  getState,
}
```

- [ ] **Step 2: Run the analyzer to find every non-exhaustive switch**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter analyze`
Expected: FAIL, `non_exhaustive_switch_expression` or `missing_enum_constant_in_switch` errors in `lib/cloud_command_service.dart` and `lib/scooter_service.dart`. Work through each one in the following steps.

- [ ] **Step 3: Wire the new commands in `CloudCommandService`**

In `lib/cloud_command_service.dart`, add to `_getCloudCommandString`:

```dart
      case CommandType.alarmArm:
        return 'alarm_arm';
      case CommandType.alarmDisarm:
        return 'alarm_disarm';
      case CommandType.alarmStop:
        return 'alarm_stop';
```

Add to `_isCommandSupportedInCloud`, in the list of `return true` cases:

```dart
      case CommandType.alarmArm:
      case CommandType.alarmDisarm:
      case CommandType.alarmStop:
```

Add to `needsConfirmation`. Arming and stopping are safe; disarming leaves the scooter unprotected, so it asks:

```dart
      case CommandType.alarmDisarm:
        return true;
      case CommandType.alarmArm:
      case CommandType.alarmStop:
        return false;
```

`_getCloudCommandParameters` has a `default: return null` and needs no change.

- [ ] **Step 4: Wire the new commands in `ScooterService`**

In `lib/scooter_service.dart`, add the three to the cloud-only list in `_bleSupportsCommand`:

```dart
  bool _bleSupportsCommand(CommandType command) {
    switch (command) {
      case CommandType.honk:
      case CommandType.alarm:
      case CommandType.alarmArm:
      case CommandType.alarmDisarm:
      case CommandType.alarmStop:
      case CommandType.locate:
      case CommandType.ping:
      case CommandType.getState:
        return false; // no BLE equivalent, cloud-only
      default:
        return true;
    }
  }
```

Add the confirmation dialog labels to `_getCommandDisplayName(BuildContext context, CommandType command)`, the switch containing `case CommandType.alarm: return FlutterI18n.translate(context, "cloud_command_alarm");`:

```dart
      case CommandType.alarmArm:
        return FlutterI18n.translate(context, "controls_alarm_arm");
      case CommandType.alarmDisarm:
        return FlutterI18n.translate(context, "controls_alarm_disarm");
      case CommandType.alarmStop:
        return FlutterI18n.translate(context, "controls_alarm_stop");
```

Add the three public methods next to the existing `alarm()`:

```dart
  Future<void> alarmArm({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.alarmArm, context: context)) {
      throw Exception("Failed to arm alarm");
    }
  }

  Future<void> alarmDisarm({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.alarmDisarm, context: context)) {
      throw Exception("Failed to disarm alarm");
    }
  }

  Future<void> alarmStop({BuildContext? context}) async {
    if (!await _executeCommand(CommandType.alarmStop, context: context)) {
      throw Exception("Failed to stop alarm");
    }
  }
```

- [ ] **Step 5: Verify**

Run: `flutter analyze`
Expected: `2 issues found` (only the pre-existing infos).

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 6: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git commit lib/command_service.dart lib/cloud_command_service.dart lib/scooter_service.dart -m "feat(cloud): add alarm arm, disarm and stop commands

Cloud-only, like the alarm siren command already is. Disarming asks for
confirmation since it leaves the scooter unprotected."
```

---

### Task 5: Read alarm state from the cloud poll

`_refreshCloudOnlineStatus()` already fetches the full scooter payload every 30s. It should keep `alarm_state` and `alarm_triggered` off it.

**Files:**
- Modify: `lib/scooter_service.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ScooterService.cloudAlarmState` (`String?`) and `ScooterService.cloudAlarmTriggered` (`bool`). Task 6 reads both.

- [ ] **Step 1: Add the fields and getters**

In `lib/scooter_service.dart`, next to `bool _isCloudOnline = false;`:

```dart
  String? _cloudAlarmState;
  bool _cloudAlarmTriggered = false;
```

Next to `bool get isCloudOnline => _isCloudOnline;`:

```dart
  String? get cloudAlarmState => _cloudAlarmState;
  bool get cloudAlarmTriggered => _cloudAlarmTriggered;
```

- [ ] **Step 2: Populate them in the poll**

In `_refreshCloudOnlineStatus()`, immediately after:

```dart
      _isCloudOnline = data['online'] == true;
```

insert:

```dart
      // Alarm state comes off the payload we already fetched, whether or not
      // BLE is connected: it has no BLE equivalent, so nothing fresher exists.
      final alarmState = data['alarm_state'];
      _cloudAlarmState = alarmState is String ? alarmState : null;
      _cloudAlarmTriggered = data['alarm_triggered'] == true;
```

- [ ] **Step 3: Clear them when the scooter is not cloud-linked**

At the top of `_refreshCloudOnlineStatus()`, in the early return:

```dart
    if (scooter?.cloudScooterId == null) {
      _isCloudOnline = false;
      _isCloudConnecting = false;
      _cloudAlarmState = null;
      _cloudAlarmTriggered = false;
      return;
    }
```

- [ ] **Step 4: Verify**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter analyze`
Expected: `2 issues found`.

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 5: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git commit lib/scooter_service.dart -m "feat(cloud): keep alarm state from the existing status poll"
```

---

### Task 6: Alarm UI in the control sheet

The control sheet already has a cloud actions block: a `Features.isCloudConnectivityEnabled` `FutureBuilder`, a `Selector` producing a `Map<CommandType, bool>` from `isCommandAvailableCached`, an "alerts" header, and `_CloudActionButton`. The alarm row goes there.

**Files:**
- Modify: `lib/control_sheet.dart`
- Modify: `assets/i18n/en.json`, `de.json`, `fr.json`, `nl.json`, `pi.json`

**Interfaces:**
- Consumes: `alarmActionFor`, `alarmStateI18nKey`, `AlarmAction` (Task 3); `ScooterService.alarmArm/alarmDisarm/alarmStop` (Task 4); `ScooterService.cloudAlarmState` (Task 5); `CommandType.alarmArm/alarmDisarm/alarmStop` (Task 4).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the i18n keys to `assets/i18n/en.json`**

Insert these next to the existing `"cloud_command_alarm"` key:

```json
    "controls_alarm_arm": "Arm alarm",
    "controls_alarm_disarm": "Disarm alarm",
    "controls_alarm_stop": "Stop alarm",
    "controls_alarm_status": "Alarm: {state}",
    "alarm_state_armed": "Armed",
    "alarm_state_delay_armed": "Arming",
    "alarm_state_disarmed": "Disarmed",
    "alarm_state_seatbox_access": "Seatbox access",
    "alarm_state_triggered_l1": "Triggered",
    "alarm_state_triggered_l2": "Alarm active",
    "alarm_state_disabled": "Disabled",
    "alarm_state_unknown": "Unknown"
```

- [ ] **Step 2: Add the same keys to `assets/i18n/de.json`**

```json
    "controls_alarm_arm": "Alarm scharf schalten",
    "controls_alarm_disarm": "Alarm entschärfen",
    "controls_alarm_stop": "Alarm stoppen",
    "controls_alarm_status": "Alarm: {state}",
    "alarm_state_armed": "Scharf",
    "alarm_state_delay_armed": "Wird scharf geschaltet",
    "alarm_state_disarmed": "Entschärft",
    "alarm_state_seatbox_access": "Sitzbankzugriff",
    "alarm_state_triggered_l1": "Ausgelöst",
    "alarm_state_triggered_l2": "Alarm aktiv",
    "alarm_state_disabled": "Deaktiviert",
    "alarm_state_unknown": "Unbekannt"
```

- [ ] **Step 3: Add the same keys to `assets/i18n/fr.json`**

```json
    "controls_alarm_arm": "Activer l'alarme",
    "controls_alarm_disarm": "Désactiver l'alarme",
    "controls_alarm_stop": "Arrêter l'alarme",
    "controls_alarm_status": "Alarme : {state}",
    "alarm_state_armed": "Activée",
    "alarm_state_delay_armed": "Activation",
    "alarm_state_disarmed": "Désactivée",
    "alarm_state_seatbox_access": "Accès au coffre",
    "alarm_state_triggered_l1": "Déclenchée",
    "alarm_state_triggered_l2": "Alarme active",
    "alarm_state_disabled": "Désactivée",
    "alarm_state_unknown": "Inconnue"
```

- [ ] **Step 4: Add the same keys to `assets/i18n/nl.json`**

```json
    "controls_alarm_arm": "Alarm inschakelen",
    "controls_alarm_disarm": "Alarm uitschakelen",
    "controls_alarm_stop": "Alarm stoppen",
    "controls_alarm_status": "Alarm: {state}",
    "alarm_state_armed": "Ingeschakeld",
    "alarm_state_delay_armed": "Inschakelen",
    "alarm_state_disarmed": "Uitgeschakeld",
    "alarm_state_seatbox_access": "Toegang tot zitkist",
    "alarm_state_triggered_l1": "Geactiveerd",
    "alarm_state_triggered_l2": "Alarm actief",
    "alarm_state_disabled": "Uitgezet",
    "alarm_state_unknown": "Onbekend"
```

- [ ] **Step 5: Add the same keys to `assets/i18n/pi.json`**

```json
    "controls_alarm_arm": "Set the watch",
    "controls_alarm_disarm": "Stand down the watch",
    "controls_alarm_stop": "Belay that racket",
    "controls_alarm_status": "Watch: {state}",
    "alarm_state_armed": "On watch",
    "alarm_state_delay_armed": "Takin' up the watch",
    "alarm_state_disarmed": "Off watch",
    "alarm_state_seatbox_access": "Raidin' the hold",
    "alarm_state_triggered_l1": "Somethin' stirs",
    "alarm_state_triggered_l2": "All hands on deck",
    "alarm_state_disabled": "No watch set",
    "alarm_state_unknown": "Lost at sea"
```

- [ ] **Step 6: Verify the JSON is valid**

Run:

```bash
cd /home/teal/src/reunu/unustasis-cloud
python3 -c "
import json
for loc in ['en','de','fr','nl','pi']:
    d = json.load(open('assets/i18n/%s.json' % loc))
    missing = [k for k in ['controls_alarm_arm','controls_alarm_disarm','controls_alarm_stop','controls_alarm_status','alarm_state_armed','alarm_state_delay_armed','alarm_state_disarmed','alarm_state_seatbox_access','alarm_state_triggered_l1','alarm_state_triggered_l2','alarm_state_disabled','alarm_state_unknown'] if k not in d]
    print(loc, 'ok' if not missing else 'MISSING %s' % missing)
"
```

Expected: `en ok`, `de ok`, `fr ok`, `nl ok`, `pi ok`.

- [ ] **Step 7: Add the alarm imports to `control_sheet.dart`**

Add to the imports at the top of `lib/control_sheet.dart`, alongside the existing `import '../domain/scooter_state.dart';`. Files directly under `lib/` in this repo use the `../` prefix for sibling directories; match that:

```dart
import '../domain/alarm_state.dart';
```

- [ ] **Step 8: Extend the availability selector**

In the cloud actions `Selector`, add the three new commands to the list it builds:

```dart
                selector: (context, s) => {
                  for (final c in const [
                    CommandType.locate,
                    CommandType.honk,
                    CommandType.alarm,
                    CommandType.alarmArm,
                    CommandType.alarmDisarm,
                    CommandType.alarmStop,
                    CommandType.ping,
                    CommandType.getState,
                  ])
                    c: s.isCommandAvailableCached(c),
                },
```

- [ ] **Step 9: Add the alarm status line and action**

Immediately after the existing alarm siren block, which reads:

```dart
                      if (available[CommandType.alarm] == true) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _CloudActionButton(
                                labelKey: "cloud_command_alarm",
                                icon: Icons.notifications_active_outlined,
                                onPressed: (context) => context.read<ScooterService>().alarm(context: context),
                              ),
                            ),
                          ],
                        ),
                      ],
```

insert:

```dart
                      Selector<ScooterService, String?>(
                        selector: (context, s) => s.cloudAlarmState,
                        builder: (context, alarmState, _) {
                          final action = alarmActionFor(alarmState);
                          if (action == null) return const SizedBox.shrink();
                          final command = switch (action) {
                            AlarmAction.arm => CommandType.alarmArm,
                            AlarmAction.disarm => CommandType.alarmDisarm,
                            AlarmAction.stop => CommandType.alarmStop,
                          };
                          if (available[command] != true) return const SizedBox.shrink();
                          final (labelKey, icon) = switch (action) {
                            AlarmAction.arm => ("controls_alarm_arm", Icons.lock_outline),
                            AlarmAction.disarm => ("controls_alarm_disarm", Icons.lock_open_outlined),
                            AlarmAction.stop => ("controls_alarm_stop", Icons.notifications_off_outlined),
                          };
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 16),
                              Center(
                                child: Text(
                                  FlutterI18n.translate(
                                    context,
                                    "controls_alarm_status",
                                    translationParams: {
                                      "state": FlutterI18n.translate(context, alarmStateI18nKey(alarmState)),
                                    },
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _CloudActionButton(
                                      labelKey: labelKey,
                                      icon: icon,
                                      onPressed: (context) => switch (action) {
                                        AlarmAction.arm => context.read<ScooterService>().alarmArm(context: context),
                                        AlarmAction.disarm =>
                                          context.read<ScooterService>().alarmDisarm(context: context),
                                        AlarmAction.stop => context.read<ScooterService>().alarmStop(context: context),
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
```

- [ ] **Step 10: Verify**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter analyze`
Expected: `2 issues found`.

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 11: Manual verification**

Open the control sheet for a cloud-linked, online scooter. Expected: an "Alarm: Armed" (or Disarmed) line under the alerts section with a matching button. Tapping disarm asks for confirmation first; arm and stop do not. The section disappears entirely when the scooter reports `disabled` or has no alarm service.

- [ ] **Step 12: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git commit lib/control_sheet.dart assets/i18n/en.json assets/i18n/de.json assets/i18n/fr.json assets/i18n/nl.json assets/i18n/pi.json -m "feat(cloud): show alarm state and offer the matching action"
```

---

### Task 7: Navigation channel choice, as a pure function

Navigation currently picks BLE or "queue until BLE returns". With the cloud available it should try cloud in between.

**Files:**
- Create: `lib/domain/nav_channel.dart`
- Test: `test/domain/nav_channel_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum NavChannel { ble, cloud, pending }` and `NavChannel navChannelFor({required bool bleReady, required bool cloudLinked, required bool cloudOnline})`. Task 8 uses both.

- [ ] **Step 1: Write the failing test**

Create `test/domain/nav_channel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/nav_channel.dart';

void main() {
  group('navChannelFor', () {
    test('BLE wins when it is ready', () {
      expect(
        navChannelFor(bleReady: true, cloudLinked: true, cloudOnline: true),
        NavChannel.ble,
      );
      expect(
        navChannelFor(bleReady: true, cloudLinked: false, cloudOnline: false),
        NavChannel.ble,
      );
    });

    test('cloud takes over when BLE is not ready', () {
      expect(
        navChannelFor(bleReady: false, cloudLinked: true, cloudOnline: true),
        NavChannel.cloud,
      );
    });

    test('a linked but offline scooter falls through to pending', () {
      expect(
        navChannelFor(bleReady: false, cloudLinked: true, cloudOnline: false),
        NavChannel.pending,
      );
    });

    test('an unlinked scooter falls through to pending', () {
      expect(
        navChannelFor(bleReady: false, cloudLinked: false, cloudOnline: true),
        NavChannel.pending,
      );
      expect(
        navChannelFor(bleReady: false, cloudLinked: false, cloudOnline: false),
        NavChannel.pending,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter test test/domain/nav_channel_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:unustasis/domain/nav_channel.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/nav_channel.dart`:

```dart
/// Where a navigation destination should be sent.
enum NavChannel {
  /// Straight over BLE to a connected scooter.
  ble,

  /// Through sunshine to a cloud-linked scooter that is online.
  cloud,

  /// Neither channel is up. Queue it and dispatch when one returns.
  pending,
}

/// Picks the channel for a navigation destination.
///
/// BLE first: it is the lower-latency path and the only one that can address a
/// scooter-side favourite by id. Cloud second. Queueing is the last resort, not
/// the normal path for a scooter that is merely out of Bluetooth range.
NavChannel navChannelFor({
  required bool bleReady,
  required bool cloudLinked,
  required bool cloudOnline,
}) {
  if (bleReady) return NavChannel.ble;
  if (cloudLinked && cloudOnline) return NavChannel.cloud;
  return NavChannel.pending;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/nav_channel_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git add lib/domain/nav_channel.dart test/domain/nav_channel_test.dart
git commit lib/domain/nav_channel.dart test/domain/nav_channel_test.dart -m "feat(cloud): pick a navigation channel from BLE and cloud readiness"
```

---

### Task 8: Send navigation destinations over cloud

Sunshine has `PUT /scooters/:id/destination` taking `latitude`, `longitude` and an optional `address`, and `DELETE /scooters/:id/destination`. Both require the `scooter_control` scope and return `{"status": "success"}`.

Today `navigation_screen._navigateToDestination` and `_navigateToFav` both do `if (!service.connected) { setPendingNavigation(dest); return; }` before calling BLE. Both funnel into one `ScooterService` method instead.

**Files:**
- Modify: `lib/cloud_service.dart`
- Modify: `lib/scooter_service.dart`
- Modify: `lib/navigation_screen.dart`

**Interfaces:**
- Consumes: `navChannelFor`, `NavChannel` (Task 7).
- Produces: `CloudService.setDestination(int scooterId, double latitude, double longitude, {String? name})` returning `Future<bool>`; `CloudService.clearDestination(int scooterId)` returning `Future<bool>`; `ScooterService.sendNavigation(NavDestination destination, {String? favouriteId})` returning `Future<void>`.

- [ ] **Step 1: Add the destination methods to `CloudService`**

In `lib/cloud_service.dart`, next to `sendCommand`, add:

```dart
  /// Sets the scooter's navigation target. Sunshine forwards it as a `navigate`
  /// command, so this reaches the scooter the same way a BLE `nav:dest` does.
  Future<bool> setDestination(int scooterId, double latitude, double longitude, {String? name}) async {
    try {
      final headers = await _getAuthHeaders();
      final body = <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        if (name != null && name.isNotEmpty) 'address': name,
      };

      final response = await http.put(
        Uri.parse('$_baseUrl/scooters/$scooterId/destination'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        log.info('Cloud destination set for scooter $scooterId');
        return true;
      } else if (response.statusCode == 401) {
        await logout();
        throw Exception('Authentication expired');
      }
      log.warning('Failed to set cloud destination: ${response.statusCode} ${_errorMessage(response.body)}');
      return false;
    } catch (e, stack) {
      log.severe('Failed to set cloud destination for scooter $scooterId', e, stack);
      return false;
    }
  }

  /// Clears the scooter's navigation target.
  Future<bool> clearDestination(int scooterId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl/scooters/$scooterId/destination'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        log.info('Cloud destination cleared for scooter $scooterId');
        return true;
      } else if (response.statusCode == 401) {
        await logout();
        throw Exception('Authentication expired');
      }
      log.warning('Failed to clear cloud destination: ${response.statusCode} ${_errorMessage(response.body)}');
      return false;
    } catch (e, stack) {
      log.severe('Failed to clear cloud destination for scooter $scooterId', e, stack);
      return false;
    }
  }
```

- [ ] **Step 2: Add the routing method to `ScooterService`**

In `lib/scooter_service.dart`, add the import:

```dart
import '../domain/nav_channel.dart';
```

Note: check the existing import block. Other domain imports in this file use `import '../domain/scooter_state.dart';`, so match that prefix exactly.

Add the method next to `setPendingNavigation`:

```dart
  /// Sends [destination] to the scooter over whichever channel is up.
  ///
  /// [favouriteId] is the scooter-side favourite id, when the destination came
  /// from the scooter's own favourites list. It only works over BLE: the
  /// favourite lives on the scooter and sunshine has no verb for it. Every other
  /// channel sends coordinates and a name, which is the only thing both systems
  /// agree on.
  Future<void> sendNavigation(NavDestination destination, {String? favouriteId}) async {
    _ensureCloudServicesInitialized();
    final scooter = currentScooter;
    final channel = navChannelFor(
      bleReady: _bleReady,
      cloudLinked: scooter?.cloudScooterId != null,
      cloudOnline: _isCloudOnline,
    );

    switch (channel) {
      case NavChannel.ble:
        if (favouriteId != null) {
          await commands.navigateFavCommand(myScooter, characteristicRepository, favouriteId);
        } else {
          await commands.navigateCommand(myScooter, characteristicRepository, destination);
        }
      case NavChannel.cloud:
        final ok = await _cloudService!.setDestination(
          scooter!.cloudScooterId!,
          destination.location.latitude,
          destination.location.longitude,
          name: destination.name,
        );
        if (!ok) {
          throw Exception("Failed to send destination via cloud");
        }
      case NavChannel.pending:
        await setPendingNavigation(destination);
    }
  }

  /// Clears the scooter's navigation target over whichever channel is up.
  Future<void> cancelNavigation() async {
    _ensureCloudServicesInitialized();
    final scooter = currentScooter;
    final channel = navChannelFor(
      bleReady: _bleReady,
      cloudLinked: scooter?.cloudScooterId != null,
      cloudOnline: _isCloudOnline,
    );

    switch (channel) {
      case NavChannel.ble:
        await commands.cancelNavigationCommand(myScooter, characteristicRepository);
      case NavChannel.cloud:
        final ok = await _cloudService!.clearDestination(scooter!.cloudScooterId!);
        if (!ok) {
          throw Exception("Failed to clear destination via cloud");
        }
      case NavChannel.pending:
        await setPendingNavigation(null);
    }
  }
```

- [ ] **Step 3: Route `_navigateToDestination` through it**

In `lib/navigation_screen.dart`, replace the body of `_navigateToDestination`:

```dart
  Future<void> _navigateToDestination(NavDestination dest) async {
    if (!await _confirmIfFarAway(dest.location)) return;
    if (!mounted) return;
    final service = context.read<ScooterService>();
    try {
      await service.sendNavigation(dest);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(FlutterI18n.translate(context, "nav_error", translationParams: {"error": e.toString()}))),
        );
      }
    }
  }
```

- [ ] **Step 4: Route `_navigateToFav` through it**

Replace the body of `_navigateToFav`:

```dart
  Future<void> _navigateToFav(NavDestination destination) async {
    if (!await _confirmIfFarAway(destination.location)) return;
    if (!mounted) return;
    final service = context.read<ScooterService>();
    try {
      // The favourite id only resolves on the scooter, so it goes along for the
      // BLE path only. Over cloud this travels as coordinates and a name.
      await service.sendNavigation(destination, favouriteId: destination.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(FlutterI18n.translate(context, "nav_error", translationParams: {"error": e.toString()}))),
      );
    }
  }
```

- [ ] **Step 5: Verify**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter analyze`
Expected: `2 issues found`.

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 6: Manual verification**

With a cloud-linked scooter, Bluetooth off, and the scooter online in sunshine: pick a destination in the navigation screen. Expected: the destination reaches the scooter without waiting for a BLE connection, and the log shows `Cloud destination set for scooter <id>`. With both Bluetooth and cloud unavailable, it still queues as pending and dispatches on the next BLE connection, as before.

- [ ] **Step 7: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git commit lib/cloud_service.dart lib/scooter_service.dart lib/navigation_screen.dart -m "feat(cloud): send navigation destinations over cloud when BLE is out

Destinations queued as pending only when neither channel is up, rather
than whenever Bluetooth is absent. Scooter-side favourite ids stay on the
BLE path, since sunshine has no verb for them; everything else travels as
coordinates and a name."
```

---

### Task 9: Make cloud authentication state observable

`CloudSettingsSection` caches `_isAuthenticated` in local state, loaded in `initState` and `didChangeDependencies`. The OAuth callback lands in `main.dart` and only logs its result, and `didChangeDependencies` does not fire on resume from an external browser, so the tile keeps offering "Connect to cloud" until the app restarts.

**Files:**
- Modify: `lib/scooter_service.dart`
- Modify: `lib/main.dart`
- Modify: `lib/stats/cloud_settings_section.dart`
- Modify: `docs/superpowers/specs/2026-07-25-cloud-channel-design.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ScooterService.isCloudAuthenticated` (`bool` getter), `ScooterService.refreshCloudAuthState()` (`Future<void>`), `ScooterService.handleOAuthCallback(Uri uri)` (`Future<bool>`). Task 10 reads `isCloudAuthenticated`.

- [ ] **Step 1: Add the state to `ScooterService`**

In `lib/scooter_service.dart`, next to `bool _isCloudOnline = false;`:

```dart
  bool _isCloudAuthenticated = false;
```

Next to `bool get isCloudOnline => _isCloudOnline;`:

```dart
  bool get isCloudAuthenticated => _isCloudAuthenticated;
```

Add the two methods next to `_maybeRefreshCloudStatus`:

```dart
  /// Re-reads whether we hold a usable cloud token, and tells the UI.
  Future<void> refreshCloudAuthState() async {
    if (!await Features.isCloudConnectivityEnabled) {
      _isCloudAuthenticated = false;
      notifyListeners();
      return;
    }
    _ensureCloudServicesInitialized();
    _isCloudAuthenticated = await _cloudService!.isAuthenticated;
    notifyListeners();
  }

  /// Completes the OAuth flow and republishes the auth state, so the settings
  /// screen updates as soon as the browser hands control back instead of
  /// waiting for the widget tree to be rebuilt from scratch.
  Future<bool> handleOAuthCallback(Uri uri) async {
    _ensureCloudServicesInitialized();
    final success = await _cloudService!.handleOAuthCallback(uri);
    await refreshCloudAuthState();
    if (success) {
      _maybeRefreshCloudStatus();
    }
    return success;
  }
```

- [ ] **Step 2: Route the deep link through `ScooterService`**

In `lib/main.dart`, `_handleDeepLink`, replace:

```dart
      Provider.of<ScooterService>(context, listen: false).cloudService.handleOAuthCallback(uri).then((success) {
        log.info(success ? 'OAuth callback handled successfully' : 'OAuth callback failed');
      });
```

with:

```dart
      Provider.of<ScooterService>(context, listen: false).handleOAuthCallback(uri).then((success) {
        log.info(success ? 'OAuth callback handled successfully' : 'OAuth callback failed');
      });
```

- [ ] **Step 3: Have `CloudSettingsSection` watch the service**

In `lib/stats/cloud_settings_section.dart`, remove the `_isAuthenticated` field and every `setState` that writes it. `_loadCloudStatus` becomes:

```dart
  Future<void> _loadCloudStatus() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final cloudEnabled = await Features.isCloudConnectivityEnabled;
      if (!mounted) return;
      setState(() {
        _isCloudEnabled = cloudEnabled;
      });
      // Auth state lives on ScooterService so the OAuth deep link can publish
      // it; this widget reads it through a Selector in build().
      await context.read<ScooterService>().refreshCloudAuthState();
    } catch (e, stack) {
      log.severe('Failed to load cloud status', e, stack);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
```

In `_logout`, replace `await _loadCloudStatus();` with:

```dart
      await context.read<ScooterService>().refreshCloudAuthState();
```

Replace the whole `build()` method with this. `Selector` comes from `package:provider/provider.dart`, already imported in this file:

```dart
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Header(FlutterI18n.translate(context, "cloud_settings_title")),
        SwitchListTile(
          secondary: const Icon(Icons.cloud_outlined),
          title: Text(FlutterI18n.translate(context, "cloud_connectivity_enable")),
          subtitle: Text(FlutterI18n.translate(context, "cloud_connectivity_description")),
          value: _isCloudEnabled,
          onChanged: (_) => _toggleCloudConnectivity(),
        ),
        if (_isCloudEnabled) ...[
          Divider(
            indent: 16,
            endIndent: 16,
            height: 24,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          // Auth state lives on ScooterService so the OAuth deep link can push it
          // here without this widget being rebuilt from scratch.
          Selector<ScooterService, bool>(
            selector: (context, s) => s.isCloudAuthenticated,
            builder: (context, isAuthenticated, _) {
              if (!isAuthenticated) {
                return ListTile(
                  leading: const Icon(Icons.login),
                  title: Text(FlutterI18n.translate(context, "cloud_connect")),
                  subtitle: Text(FlutterI18n.translate(context, "cloud_connect_description")),
                  onTap: _authenticateWithCloud,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_done, color: Colors.green),
                    title: Text(FlutterI18n.translate(context, "cloud_connected")),
                    subtitle: Text(FlutterI18n.translate(context, "cloud_logout_description")),
                    trailing: const Icon(Icons.logout, color: Colors.red),
                    onTap: _logout,
                  ),
                  ListTile(
                    leading: const Icon(Icons.open_in_browser),
                    title: Text(FlutterI18n.translate(context, "cloud_dashboard")),
                    subtitle: Text(FlutterI18n.translate(context, "cloud_dashboard_description")),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openCloudDashboard,
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
```

- [ ] **Step 4: Correct the spec**

The spec's section 4 says the settings row gives "an action to link it". The linking flow (`_linkToCloudScooter`, `_linkScooter`, `_CloudScooterSelectionDialog`) is private to `_ScooterScreenState` and closes over its `savedScooter`. Extracting it is a larger change than this work justifies, so Task 10 navigates to the screen that owns the control instead.

In `docs/superpowers/specs/2026-07-25-cloud-channel-design.md`, replace:

```
`getMostRecentScooter()` when none is connected, with an action to link it. That
```

with:

```
`getMostRecentScooter()` when none is connected, with an action that opens the
scooter screen where the linking control lives. That
```

- [ ] **Step 5: Verify**

Run: `cd /home/teal/src/reunu/unustasis-cloud && flutter analyze`
Expected: `2 issues found`.

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 6: Manual verification**

In Settings, enable cloud connectivity and tap "Connect to cloud". Complete the login in the browser. Expected: on returning to the app, the tile immediately reads "Connected to cloud" with no restart.

- [ ] **Step 7: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git commit lib/scooter_service.dart lib/main.dart lib/stats/cloud_settings_section.dart docs/superpowers/specs/2026-07-25-cloud-channel-design.md -m "fix(cloud): update the settings tile as soon as OAuth returns

The section cached auth state locally and only reloaded it in initState
and didChangeDependencies, neither of which fires on resume from an
external browser, so it took an app restart to show as connected.

Reported by Zanooda on #148."
```

---

### Task 10: Surface the linking step in cloud settings

Nothing tells a freshly authenticated user that linking a scooter is the other half of the setup. Zanooda signed in, turned Bluetooth off, and saw "disconnected" with no explanation.

**Files:**
- Modify: `lib/stats/cloud_settings_section.dart`

**Interfaces:**
- Consumes: `ScooterService.isCloudAuthenticated` (Task 9).
- Produces: nothing.

- [ ] **Step 1: Add the imports**

At the top of `lib/stats/cloud_settings_section.dart`:

```dart
import '../domain/saved_scooter.dart';
import 'scooter_screen.dart';
```

- [ ] **Step 2: Resolve which scooter to report on**

Add this method to `_CloudSettingsSectionState`. It matches the resolution `navigation_screen._getCurrentSavedScooter` uses:

```dart
  Future<SavedScooter?> _scooterToLink() async {
    final service = context.read<ScooterService>();
    return service.currentScooter ?? await service.getMostRecentScooter();
  }
```

- [ ] **Step 3: Add the linking row**

In `build()`, inside the `Column` the `Selector` builder returns when authenticated (the one holding the "Connected to cloud" and "Open cloud dashboard" tiles), add this after the "Open cloud dashboard" `ListTile`:

```dart
            FutureBuilder<SavedScooter?>(
              future: _scooterToLink(),
              builder: (context, snapshot) {
                final scooter = snapshot.data;
                if (scooter == null) return const SizedBox.shrink();
                final linked = scooter.cloudScooterId != null;
                return ListTile(
                  leading: Icon(linked ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
                  title: Text(FlutterI18n.translate(context, linked ? "cloud_linked_to" : "cloud_not_linked")),
                  subtitle: Text(
                    linked
                        ? (scooter.cloudScooterName ?? scooter.name)
                        : FlutterI18n.translate(context, "cloud_link_hint"),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ScooterScreen()),
                  ),
                );
              },
            ),
```

- [ ] **Step 4: Add the `cloud_link_hint` key to all five locales**

`assets/i18n/en.json`:

```json
    "cloud_link_hint": "Link this scooter to control it without Bluetooth",
```

`assets/i18n/de.json`:

```json
    "cloud_link_hint": "Verknüpfe diesen Roller, um ihn ohne Bluetooth zu steuern",
```

`assets/i18n/fr.json`:

```json
    "cloud_link_hint": "Associez ce scooter pour le contrôler sans Bluetooth",
```

`assets/i18n/nl.json`:

```json
    "cloud_link_hint": "Koppel deze scooter om hem zonder Bluetooth te bedienen",
```

`assets/i18n/pi.json`:

```json
    "cloud_link_hint": "Bind this vessel to yer fleet to command her from afar",
```

- [ ] **Step 5: Verify the JSON**

Run:

```bash
cd /home/teal/src/reunu/unustasis-cloud
python3 -c "
import json
for loc in ['en','de','fr','nl','pi']:
    d = json.load(open('assets/i18n/%s.json' % loc))
    print(loc, 'ok' if 'cloud_link_hint' in d else 'MISSING')
"
```

Expected: all five `ok`.

- [ ] **Step 6: Verify**

Run: `flutter analyze`
Expected: `2 issues found`.

Run: `flutter test`
Expected: All tests passed.

- [ ] **Step 7: Manual verification**

Sign in to the cloud with an unlinked scooter saved. Expected: the cloud settings section shows "Not linked to cloud" with the hint, and tapping it opens the scooter screen where the link button lives. Once linked, the row shows the cloud scooter's name.

- [ ] **Step 8: Commit**

```bash
cd /home/teal/src/reunu/unustasis-cloud
git commit lib/stats/cloud_settings_section.dart assets/i18n/en.json assets/i18n/de.json assets/i18n/fr.json assets/i18n/nl.json assets/i18n/pi.json -m "feat(cloud): show link status in cloud settings

Signing in is only half the setup, and nothing said so. Reported by
Zanooda on #148."
```

---

## Not in this plan

- PR #148 review item 4 (seatbox and controls disabled after connect). Fixed by PR #153, still open. Merge main again once it lands.
- The `ScooterChannel` refactor replacing per-call-site branching with a router.
- `play_sound`, trips, events, log bundles, the wider `telemetry` block, alarm settings, reconciling favourites with `saved_destinations`.
