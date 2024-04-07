import 'package:flutter/material.dart';
import 'package:sticky_headers/sticky_headers/widget.dart';
import 'package:unustasis/scooter_service.dart';

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
                    StreamBuilder<int>(
                      stream: widget.service.primarySOC,
                      builder: (context, snapshot) {
                        return ListTile(
                            title: const Text("Primary Battery"),
                            subtitle: Text(snapshot.hasData
                                ? "${snapshot.data}%"
                                : "Unknown"));
                      },
                    ),
                    StreamBuilder<int>(
                      stream: widget.service.secondarySOC,
                      builder: (context, snapshot) {
                        return ListTile(
                            title: const Text("Secondary Battery"),
                            subtitle: Text(snapshot.hasData
                                ? "${snapshot.data}%"
                                : "Unknown"));
                      },
                    ),
                  ],
                ),
              )),
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
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Text(title),
          ),
        ],
      ),
    );
  }
}
