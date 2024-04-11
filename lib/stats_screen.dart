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
        actions: [
          StreamBuilder<DateTime?>(
              stream: widget.service.lastPing,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      snapshot.data!.calculateTimeDifferenceInShort(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(
                      width: 4,
                    ),
                    const Icon(
                      Icons.schedule_rounded,
                      color: Colors.white70,
                    ),
                    const SizedBox(
                      width: 32,
                    ),
                  ],
                );
              }),
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
        child: StreamBuilder<DateTime?>(
            stream: widget.service.lastPing,
            builder: (context, lastPing) {
              bool dataIsOld = !lastPing.hasData ||
                  lastPing.hasData &&
                      lastPing.data!.difference(DateTime.now()).inMinutes > 5;
              return ListView(
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
                                            name: "Primary Battery",
                                            soc: socSnap.data ?? 0,
                                            infos: [
                                              "Used for driving",
                                              "Cycles: ${cycleSnap.data ?? "Unknown"}",
                                            ],
                                            old: dataIsOld,
                                          ),
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
                                          child: _batteryCard(
                                            name: "Secondary Battery",
                                            soc: socSnap.data ?? 0,
                                            infos: [
                                              "Backup battery",
                                              "Cycles: ${cycleSnap.data ?? "Unknown"}",
                                            ],
                                            old: dataIsOld,
                                          ),
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
                                      name: "Connectivity Battery",
                                      soc: snapshot.data ?? 0,
                                      infos: [
                                        'Used for smart features',
                                        cbbCharging.hasData
                                            ? cbbCharging.data == true
                                                ? "Charging"
                                                : "Not charging"
                                            : "Unknown state",
                                      ],
                                      old: dataIsOld,
                                    );
                                  });
                            },
                          ),
                          StreamBuilder<int?>(
                            stream: widget.service.auxSOC,
                            builder: (context, snapshot) {
                              return _batteryCard(
                                name: "AUX Battery",
                                soc: snapshot.data ?? 0,
                                infos: ['Used to keep scooter alive'],
                                old: dataIsOld,
                              );
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
                              subtitle: Text(snapshot.hasData
                                  ? snapshot.data!.name
                                  : "Unknown"),
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
                    header: const Header("Settings"),
                    content: Column(
                      children: [
                        // TODO: Move "Forget scooter" here
                        ListTile(
                          title: const Text(
                              "Scooter color (will update on restart)"),
                          subtitle: DropdownButtonFormField(
                            padding: const EdgeInsets.only(top: 4),
                            value: color,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.all(16),
                            ),
                            dropdownColor:
                                Theme.of(context).colorScheme.background,
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
              );
            }),
      ),
    );
  }

  Widget _batteryCard(
      {required String name,
      required int soc,
      required List<String> infos,
      bool old = false}) {
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
              color: old
                  ? Theme.of(context).colorScheme.surface
                  : soc < 15
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
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

extension DateTimeExtension on DateTime {
  String calculateTimeDifferenceInShort() {
    final originalDate = DateTime.now();
    final difference = originalDate.difference(this);

    if ((difference.inDays / 7).floor() >= 1) {
      return '1W';
    } else if (difference.inDays >= 2) {
      return '${difference.inDays}D';
    } else if (difference.inDays >= 1) {
      return '1D';
    } else if (difference.inHours >= 2) {
      return '${difference.inHours}H';
    } else if (difference.inHours >= 1) {
      return '1H';
    } else if (difference.inMinutes >= 2) {
      return '${difference.inMinutes}M';
    } else if (difference.inMinutes >= 1) {
      return '1M';
    } else {
      return 'NOW';
    }
  }
}
