# Wear OS companion app

A small native Kotlin/Compose app for Wear OS 3+ that offers the same functionality as the
Android home screen widget: scooter state, battery levels, and the lock/unlock and open-seat
actions — as a watch app and as a tile.

## How it works

The watch is **not** paired with the scooter and never talks BLE. It is a remote control for the
phone, and it reuses the seam the home screen widget already defines:

| Direction | Transport | Phone side |
|---|---|---|
| State (phone → watch) | `DataClient`, path `/unustasis/state` | `WearBridge` reads the `home_widget` prefs store — the same one Glance renders from — whenever `HomeWidgetReceiver` gets an update broadcast |
| Commands (watch → phone) | `MessageClient`, path `/unustasis/action` | `WearMessageService` fires `unustasis://lock\|unlock\|openseat` through `HomeWidgetBackgroundIntent`, exactly like a widget button |

Because commands re-enter the widget's own broadcast, they inherit Dart's pending-action
persistence and background-service startup for free, and progress flows back to the watch as
ordinary widget state. **No Dart code is involved in the bridge.**

State travels as a `DataItem` rather than a message so it is persisted by the Data Layer: the
tile can render, and the app can open, with last-known values even while the phone is out of
range.

## Building

The watch APK is a separate artifact — `flutter build apk` does **not** build it.

```bash
# from the repository root; also generates android/gradlew, which is gitignored
flutter build apk --release

cd android
./gradlew :wear:assembleRelease
# -> build/wear/outputs/apk/release/wear-release.apk
```

`:wear` deliberately does not apply the Flutter Gradle plugin, but the root `build.gradle`
declares `evaluationDependsOn(':app')` for every subproject, so a working Flutter SDK and
`android/local.properties` are still required to configure the build.

## Signing (important)

The Wearable Data Layer only routes between apps that share **both** an application ID and a
signing certificate. The module is therefore wired to:

- `applicationId "de.freal.unustasis"` (namespace stays `de.freal.unustasis.wear`)
- `applicationIdSuffix ".debug"` on debug builds, mirroring the phone app
- `android/key.properties` for release signing, the same keystore the phone app uses

If lock/unlock silently does nothing, check these first:

```bash
aapt dump badging <phone.apk> | head -1
aapt dump badging <wear.apk>  | head -1     # package names must match
apksigner verify --print-certs <phone.apk>
apksigner verify --print-certs <wear.apk>   # certificates must match
```

## Installing on a watch

Enable developer options and ADB/Wi-Fi debugging on the watch, then:

```bash
adb connect <watch-ip>:5555
adb -s <watch-ip>:5555 install -r build/wear/outputs/apk/release/wear-release.apk
```

## Localization

Scooter state text ("Parked", "Ready to drive", …) arrives from the phone **already localized** —
the phone writes it into the widget store via `getNameStatic()`, and the watch just displays it.
Only a handful of watch-owned strings live in `res/values*/strings.xml`.

One consequence: the watch follows the **system** locale, so it does not honour an in-app
language override set on the phone.
