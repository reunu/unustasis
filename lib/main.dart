import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
  BluetoothDevice? myScooter;
  String debugText = "";

  void _startScanning() async {
    for (var device in FlutterBluePlus.connectedDevices) {
      if (device.advName == "unu Scooter" && !foundScooters.contains(device)) {
        foundScooters.add(device);
      }
    }
    myScooter = null;
    // start scan
    FlutterBluePlus.startScan();
    setState(() {
      scanning = true;
    });
    var subscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (results.isNotEmpty) {
          ScanResult r = results.last; // the most recently found device
          log('${r.device.remoteId}: "${r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : "unnamed"}" found!');
          if (r.advertisementData.advName == "unu Scooter" &&
              !foundScooters.contains(r.device)) {
            foundScooters.add(r.device);
          }
        }
      },
      onError: (e) => log(e.toString()),
    );
    FlutterBluePlus.cancelWhenScanComplete(subscription);
    Future.delayed(const Duration(seconds: 10), () {
      FlutterBluePlus.stopScan();
      setState(() {
        scanning = false;
      });
    });
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
    await myScooter?.discoverServices();
    setState(() {
      debugText = "Unlocking...";
    });
    myScooter?.servicesList.forEach((service) {
      log("Service: ${service.uuid.toString()}");
      service.characteristics.forEach((characteristic) {
        log("Characteristic: ${characteristic.uuid.toString()}");
        if (service.uuid.toString() == "9A590000-6E67-5D0D-AAB9-AD9126B66F91" &&
            characteristic.uuid.toString() ==
                "9A590001-6E67-500D-AAB9-AD9126866F91") {
          setState(() {
            debugText = "Found characteristic...";
          });
          characteristic.write(ascii.encode("scooter:state unlock"),
              withoutResponse: true);
        }
      });
    });
  }

  void _lock() async {
    await myScooter?.discoverServices(); // this is so redundant
    myScooter?.servicesList.forEach((service) {
      log("Service: ${service.uuid.toString()}");
      service.characteristics.forEach((characteristic) {
        log("Characteristic: ${characteristic.uuid.toString()}");
        if (service.uuid.toString() == "9A590000-6E67-5D0D-AAB9-AD9126B66F91" &&
            characteristic.uuid.toString() ==
                "9A590001-6E67-500D-AAB9-AD9126866F91") {
          log("Unlocking...");
          characteristic.write(ascii.encode("scooter:state lock"),
              withoutResponse: true);
        }
      });
    });
  }

  @override
  void initState() {
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
