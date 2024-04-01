import 'package:flutter/material.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/no_scooter.dart';
import 'package:unustasis/scooter_service.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  final ScooterService service = ScooterService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unustasis',
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: Colors.blue,
          onPrimary: Colors.white,
          secondary: Colors.green,
          onSecondary: Colors.white,
          background: Colors.grey.shade900,
          onBackground: Colors.white,
          surface: Colors.grey.shade800,
          onSurface: Colors.white,
          error: Colors.red,
          onError: Colors.white,
        ),
        /* dark theme settings */
      ),
      themeMode: ThemeMode.dark,
      home: HomeScreen(
        scooterService: service,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  ScooterService scooterService = ScooterService();
  bool scanning = false;
  bool connected = false;

  @override
  void initState() {
    super.initState();
    scooterService.connected.listen((event) {
      setState(() {
        connected = event;
      });
    });
    scooterService.scanning.listen((event) {
      setState(() {
        scanning = event;
      });
    });
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
                children: connected
                    ? [const Text("Connected!")]
                    : [NoScooterMsg(scanning: scanning)],
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: connected ? scooterService.unlock : null,
                icon: const Icon(Icons.lock_open),
                label: const Text("Unlock"),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: connected ? scooterService.lock : null,
                icon: const Icon(Icons.lock),
                label: const Text("Lock"),
              ),
              const SizedBox(height: 32),
              Text(
                '''
Scanning: $scanning,
My scooter: ${scooterService.myScooter?.remoteId.toString() ?? "none"}''',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: scanning ? null : scooterService.start,
        tooltip: 'Refresh',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
