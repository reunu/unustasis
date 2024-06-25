<img src='images/readme_logo.png' width='360'>

```
Anastasis, noun - a recovery from a debilitating condition. Rebirth, resurrection.
```
  
This is an open-source, BLE-only app for the Unu Scooter Pro, created as an alternative by the community after unu motors filed for bankruptcy.
This app does not use any offical code by unu, but has since been endorsed and supported by emco electroroller as new owners of the unu brand. Interested in contributing? Join the [Unu Community Discord](https://discord.gg/fa63HJYaP4) or create an issue right here on GitHub!

## Getting Started

### Using this app

If you just want to use this app, go into the "Releases" section on this page and download the latest APK file. The app is also available as proe-release through Google Play and Apple TestFlight, but that will change shortly.

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



