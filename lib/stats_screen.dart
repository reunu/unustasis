import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticky_headers/sticky_headers/widget.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/scooter_state.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({required this.service, super.key});

  final ScooterService service;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int color = 0;

  @override
  void initState() {
    super.initState();
    getColor();
  }

  void getColor() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      color = prefs.getInt("color") ?? 0;
    });
  }

  void setColor(int newColor) async {
    setState(() {
      color = newColor;
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt("color", color);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Info'),
        backgroundColor: Colors.black,
        actions: const [
          // Text(
          //   "2d",
          //   style: TextStyle(
          //     fontWeight: FontWeight.bold,
          //     color: Colors.white70,
          //   ),
          // ),
          // SizedBox(
          //   width: 4,
          // ),
          // Icon(
          //   Icons.schedule_rounded,
          //   color: Colors.white70,
          // ),
          // SizedBox(
          //   width: 32,
          // ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Theme.of(context).colorScheme.background,
            ],
          ),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            StickyHeader(
              header: const Header("Battery"),
              content: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        StreamBuilder<int?>(
                          stream: widget.service.primarySOC,
                          builder: (context, socSnap) {
                            return StreamBuilder<int?>(
                                stream: widget.service.primaryCycles,
                                builder: (context, cycleSnap) {
                                  return Expanded(
                                    child: _batteryCard(
                                        "Primary Battery", socSnap.data ?? 0, [
                                      "Used for driving",
                                      "Cycles: ${cycleSnap.data ?? "Unknown"}",
                                    ]),
                                  );
                                });
                          },
                        ),
                        StreamBuilder<int?>(
                          stream: widget.service.secondarySOC,
                          builder: (context, socSnap) {
                            if (!socSnap.hasData || socSnap.data == 0) {
                              return Container();
                            }
                            return StreamBuilder<int?>(
                                stream: widget.service.secondaryCycles,
                                builder: (context, cycleSnap) {
                                  return Expanded(
                                    child: _batteryCard("Secondary Battery",
                                        socSnap.data ?? 0, [
                                      "Backup battery",
                                      "Cycles: ${cycleSnap.data ?? "Unknown"}",
                                    ]),
                                  );
                                });
                          },
                        ),
                      ],
                    ),
                    StreamBuilder<int?>(
                      stream: widget.service.cbbSOC,
                      builder: (context, snapshot) {
                        return StreamBuilder<bool?>(
                            stream: widget.service.cbbCharging,
                            builder: (context, cbbCharging) {
                              return _batteryCard(
                                  "Connectivity Battery", snapshot.data ?? 0, [
                                'Used for smart features',
                                cbbCharging.hasData
                                    ? cbbCharging.data == true
                                        ? "Charging"
                                        : "Not charging"
                                    : "Unknown state",
                              ]);
                            });
                      },
                    ),
                    StreamBuilder<int?>(
                      stream: widget.service.auxSOC,
                      builder: (context, snapshot) {
                        return _batteryCard("AUX Battery", snapshot.data ?? 0,
                            ['Used to keep scooter alive']);
                      },
                    ),
                  ],
                ),
              ),
            ),
            StickyHeader(
              header: const Header("Scooter"),
              content: Column(
                children: [
                  StreamBuilder<ScooterState?>(
                    stream: widget.service.state,
                    builder: (context, snapshot) {
                      return ListTile(
                        title: const Text("State"),
                        subtitle: Text(
                            snapshot.hasData ? snapshot.data!.name : "Unknown"),
                      );
                    },
                  ),
                  StreamBuilder<ScooterState?>(
                    stream: widget.service.state,
                    builder: (context, snapshot) {
                      return ListTile(
                        title: const Text("State description"),
                        subtitle: Text(snapshot.hasData
                            ? snapshot.data!.description
                            : "Unknown"),
                      );
                    },
                  ),
                  FutureBuilder(
                      future: widget.service.getSavedScooter(),
                      builder: (context, snapshot) {
                        return ListTile(
                          title: const Text("Scooter ID"),
                          subtitle: Text(snapshot.hasData
                              ? snapshot.data!.toString()
                              : "Unknown"),
                        );
                      }),
                ],
              ),
            ),
            StickyHeader(
              header: Header("Settings"),
              content: Column(
                children: [
                  // TODO: Move "Forget scooter" here
                  ListTile(
                    title: const Text("Scooter color (will update on restart)"),
                    subtitle: DropdownButtonFormField(
                      padding: const EdgeInsets.only(top: 4),
                      value: color,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.all(16),
                      ),
                      dropdownColor: Theme.of(context).colorScheme.background,
                      items: const [
                        DropdownMenuItem(
                          value: 0,
                          child: Text("Black"),
                        ),
                        DropdownMenuItem(
                          value: 1,
                          child: Text("White"),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text("Pine"),
                        ),
                        DropdownMenuItem(
                          value: 3,
                          child: Text("Stone"),
                        ),
                        DropdownMenuItem(
                          value: 4,
                          child: Text("Coral"),
                        ),
                        DropdownMenuItem(
                          value: 5,
                          child: Text("Red"),
                        ),
                        DropdownMenuItem(
                          value: 6,
                          child: Text("Blue"),
                        ),
                      ],
                      onChanged: (newColor) {
                        setColor(newColor!);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _batteryCard(String name, int soc, List<String> infos) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onBackground
                      .withOpacity(0.5)),
            ),
            const SizedBox(height: 8.0),
            Text("$soc%", style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 4.0),
            LinearProgressIndicator(
              value: soc / 100,
              borderRadius: BorderRadius.circular(16.0),
              minHeight: 16,
              color:
                  soc < 15 ? Colors.red : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12.0),
            ...infos.map((info) => Text(info)),
          ],
        ),
      ),
    );
  }
}

class Header extends StatelessWidget {
  const Header(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      //color: Theme.of(context).colorScheme.background,
      child: Row(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall!
                    .copyWith(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
