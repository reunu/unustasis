import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/no_scooter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool linked = false, scanning = false;
  List<BluetoothDevice> foundScooters = [];
  String? savedScooterId;
  BluetoothDevice? myScooter;
  String debugText = "";

  void _startScanning() async {
    myScooter = null;
    // keep track of scanning status
    FlutterBluePlus.isScanning.listen((event) {
      setState(() {
        scanning = event;
      });
    });
    // see if the app is connected to the scooter already
    for (var device in FlutterBluePlus.connectedDevices) {
      if (device.advName == "unu Scooter") {
        foundScooters.add(device);
      }
    }
    // see if the phone is connected to the scooter already
    List<BluetoothDevice> systemDevices = await FlutterBluePlus.systemDevices;
    for (var device in systemDevices) {
      log("${device.advName} - ${device.remoteId}");
      if (device.advName == "unu Scooter" ||
          device.remoteId.toString() == await _getSavedScooter()) {
        foundScooters.add(device);
      }
    }
    // start scanning for scooters
    FlutterBluePlus.startScan(
      withKeywords: ["unu"],
      timeout: const Duration(seconds: 30),
    );
    var subscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (results.isNotEmpty) {
          ScanResult r = results.last; // the most recently found device
          setState(() {
            debugText =
                ('${r.device.remoteId}: "${r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : "unnamed"}" found!');
          });
          if (r.advertisementData.advName == "unu Scooter" &&
              !foundScooters.contains(r.device)) {
            foundScooters.add(r.device);
          }
        }
      },
      onError: (e) => log(e.toString()),
      onDone: () => log("Scan complete!"),
    );
    FlutterBluePlus.cancelWhenScanComplete(subscription);
  }

  void _connect(BluetoothDevice scooter) async {
    log("Connecting to ${scooter.advName}...");
    if (scooter.isConnected) {
      log("Already connected!");
      await scooter.discoverServices();
      setState(() {
        linked = true;
        myScooter = scooter;
      });
      return;
    }
    try {
      await scooter.connect(
        timeout: const Duration(seconds: 10),
      );
      setSavedScooter(scooter.remoteId.toString());
      log("Linked to ${scooter.advName}!");
      await scooter.discoverServices();
      setState(() {
        linked = true;
        myScooter = scooter;
      });
    } catch (e) {
      setState(() {
        debugText = e.toString();
      });
      log(e.toString());
      return;
    }
  }

  void _unlock() async {
    await myScooter?.discoverServices(); // this is so redundant
    myScooter?.servicesList
        .firstWhere((service) {
          return service.serviceUuid.toString() ==
              "9a590000-6e67-5d0d-aab9-ad9126b66f91";
        })
        .characteristics
        .firstWhere((char) {
          return char.characteristicUuid.toString() ==
              "9a590001-6e67-5d0d-aab9-ad9126b66f91";
        })
        .write(ascii.encode("scooter:state unlock"));
  }

  void _lock() async {
    await myScooter?.discoverServices(); // this is so redundant
    myScooter?.servicesList
        .firstWhere((service) {
          return service.serviceUuid.toString() ==
              "9a590000-6e67-5d0d-aab9-ad9126b66f91";
        })
        .characteristics
        .firstWhere((char) {
          return char.characteristicUuid.toString() ==
              "9a590001-6e67-5d0d-aab9-ad9126b66f91";
        })
        .write(ascii.encode("scooter:state lock"));
  }

  Future<String?> _getSavedScooter() async {
    if (savedScooterId != null) {
      return savedScooterId;
    }
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString("savedScooterId");
  }

  void setSavedScooter(String id) async {
    setState(() {
      savedScooterId = id;
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("savedScooterId", id);
  }

  @override
  void initState() {
    _getSavedScooter();
    _startScanning();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text("Unustasis"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 16),
              ListView(
                shrinkWrap: true,
                children: foundScooters.isEmpty
                    ? [NoScooterMsg(scanning: scanning)]
                    : foundScooters.map((scooter) {
                        return ListTile(
                          title: Text(
                            scooter.advName +
                                (scooter.isConnected ? " (connected)" : ""),
                            textAlign: TextAlign.center,
                          ),
                          subtitle: Text(
                            scooter.remoteId.toString(),
                            textAlign: TextAlign.center,
                          ),
                          onTap: () => _connect(scooter),
                          tileColor: scooter == myScooter
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.5)
                              : Colors.grey.shade300,
                        );
                      }).toList(),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: myScooter == null ? null : _unlock,
                icon: const Icon(Icons.lock_open),
                label: const Text("Unlock"),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: myScooter == null ? null : _lock,
                icon: const Icon(Icons.lock),
                label: const Text("Lock"),
              ),
              const SizedBox(height: 32),
              Text(
                '''Linked: $linked,
Scanning: $scanning,
Found: ${foundScooters.length},
My scooter: ${myScooter?.remoteId.toString() ?? "none"}''',
                textAlign: TextAlign.center,
              ),
              Text(debugText),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: scanning ? null : _startScanning,
        tooltip: 'Refresh',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
