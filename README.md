<img src='images/readme_logo.png' width='360'>

```
Anastasis, noun - a recovery from a debilitating condition. Rebirth, resurrection.
```
  
This is an attempt at an inofficial, BLE-only app for the Unu Scooter Pro after the official app was shut down due to bancruptcy.
This app does NOT use any offical code by Unu, and is not endorsed by unu Motors GmbH in any way. Interested in contributing? Join the [Unu Community Discord](https://discord.gg/fa63HJYaP4)!

## Getting Started

### Using this app

If you just want to use this app, go into the "Releases" section on this page and download the latest APK file. We also intend to publish this app to the Google Play and Apple App Stores once a base level of features and stability has been reached.

### Building this app yourself

This app is made in Flutter for cross-platform functionality, UI performance, and rapid development. To build it on your system, [follow this getting-started guide](https://docs.flutter.dev/get-started/install) to install the Flutter SDK and required Android or iOS SDKs.

Run the following command in the root of this project to install and start the development version on your device:

```
flutter run
```

To get the map preview working, you need to [create a Stadia API key](https://stadiamaps.com) (free tier will suffice) and launch the app via this command:

```
flutter run --dart-define='STADIA_TOKEN=<your-api-key>'
```

### Contributing

Pull requests are very welcome, as I can only test on the few (Android) devices I own and therefore depend on any help I can get.



