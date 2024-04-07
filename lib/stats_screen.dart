import 'package:flutter/material.dart';
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Info'),
      ),
      body: ListView(
        shrinkWrap: true,
        children: [
          StickyHeader(
            header: _header("Battery"),
            content: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                children: [
                  StreamBuilder<int?>(
                    stream: widget.service.primarySOC,
                    builder: (context, snapshot) {
                      return ListTile(
                          title: const Text("Primary Battery"),
                          subtitle: Text(snapshot.hasData
                              ? "${snapshot.data}%"
                              : "Unknown"));
                    },
                  ),
                  StreamBuilder<int?>(
                    stream: widget.service.secondarySOC,
                    builder: (context, snapshot) {
                      return ListTile(
                          title: const Text("Secondary Battery"),
                          subtitle: Text(snapshot.hasData
                              ? "${snapshot.data}%"
                              : "Unknown"));
                    },
                  ),
                  StreamBuilder<int?>(
                    stream: widget.service.internalCbbSOC,
                    builder: (context, snapshot) {
                      return ListTile(
                          title: const Text("Connectivity Battery"),
                          subtitle: Text(snapshot.hasData
                              ? "${snapshot.data}%"
                              : "Unknown"));
                    },
                  ),
                ],
              ),
            ),
          ),
          StickyHeader(
            header: _header("Scooter"),
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
              ],
            ),
          ),
          StickyHeader(
            header: _header("Debug"),
            content: Column(
              children: [
                StreamBuilder<String?>(
                  stream: widget.service.stateRaw,
                  builder: (context, snapshot) {
                    return ListTile(
                      title: const Text("State string"),
                      subtitle: Text(snapshot.hasData
                          ? snapshot.data!.replaceAll(" ", "#")
                          : "Unknown"),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String title) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Text(title),
          ),
        ],
      ),
    );
  }
}
