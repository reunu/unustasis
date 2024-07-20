import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/domain/theme_helper.dart';
import 'package:unustasis/geo_helper.dart';
import 'package:unustasis/scooter_service.dart';

class ScooterSection extends StatefulWidget {
  const ScooterSection({
    super.key,
    required this.service,
    required this.dataIsOld,
  });

  final ScooterService service;
  final bool dataIsOld;

  @override
  State<ScooterSection> createState() => _ScooterSectionState();
}

class _ScooterSectionState extends State<ScooterSection> {
  int color = 1;
  String? nameCache;
  TextEditingController nameController = TextEditingController();
  FocusNode nameFocusNode = FocusNode();

  void setColor(int newColor) async {
    setState(() {
      color = newColor;
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt("color", color);
  }

  void setupInitialColor() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      color = prefs.getInt("color") ?? 1;
    });
  }

  @override
  void initState() {
    super.initState();
    setupInitialColor();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shrinkWrap: true,
      children: [
        StreamBuilder<String?>(
          stream: widget.service.scooterName,
          builder: (context, name) {
            nameController.text = name.data ?? "";
            return StreamBuilder<bool>(
                stream: widget.service.connected,
                builder: (context, connected) {
                  return ListTile(
                    title: Text(FlutterI18n.translate(context, "stats_name")),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        enabled: connected.data ?? false,
                        controller: TextEditingController(
                            text: name.data ??
                                FlutterI18n.translate(
                                    context, "stats_no_name")),
                        focusNode: nameFocusNode,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          //labelText: FlutterI18n.translate(context, "stats_name"),
                        ),
                        onChanged: (value) {
                          nameCache = value;
                        },
                        onSubmitted: (value) {
                          widget.service.renameSavedScooter(name: value);
                        },
                        onTapOutside: (event) {
                          print(
                              "Tapped outside, saving ${nameController.text}");
                          if (nameCache != null) {
                            widget.service.renameSavedScooter(name: nameCache!);
                          }
                          nameFocusNode.unfocus();
                        },
                      ),
                    ),
                  );
                });
          },
        ),
        const SizedBox(height: 4),
        ListTile(
          //leading: const Icon(Icons.color_lens_outlined),
          title: Text(FlutterI18n.translate(context, "settings_color")),
          subtitle: DropdownButtonFormField(
            padding: const EdgeInsets.only(top: 8),
            value: color,
            isExpanded: true,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.all(16),
              border: OutlineInputBorder(),
            ),
            dropdownColor: Theme.of(context).colorScheme.surface,
            items: [
              DropdownMenuItem(
                value: 0,
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(
                              color: Colors.grey.shade500,
                              width: 1,
                              strokeAlign: BorderSide.strokeAlignOutside),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(FlutterI18n.translate(context, "color_black")),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 1,
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(
                              color: Colors.grey.shade500,
                              width: 1,
                              strokeAlign: BorderSide.strokeAlignOutside),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(FlutterI18n.translate(context, "color_white")),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 2,
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green.shade900,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(FlutterI18n.translate(context, "color_green")),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 3,
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(FlutterI18n.translate(context, "color_gray")),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 4,
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.deepOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(FlutterI18n.translate(context, "color_orange")),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 5,
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(FlutterI18n.translate(context, "color_red")),
                  ],
                ),
              ),
              DropdownMenuItem(
                value: 6,
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(FlutterI18n.translate(context, "color_blue")),
                  ],
                ),
              ),
            ],
            onChanged: (newColor) {
              setColor(newColor!);
            },
          ),
        ),
        StreamBuilder<ScooterState?>(
          stream: widget.service.state,
          builder: (context, snapshot) {
            return ListTile(
              title: Text(FlutterI18n.translate(context, "stats_state")),
              subtitle: Text(snapshot.hasData
                  ? snapshot.data!.name(context)
                  : FlutterI18n.translate(context, "stats_unknown")),
            );
          },
        ),
        StreamBuilder<ScooterState?>(
          stream: widget.service.state,
          builder: (context, snapshot) {
            return ListTile(
              title: Text(
                  FlutterI18n.translate(context, "stats_state_description")),
              subtitle: Text(snapshot.hasData
                  ? snapshot.data!.description(context)
                  : FlutterI18n.translate(context, "stats_unknown")),
            );
          },
        ),
        FutureBuilder<List<String>>(
            future: widget.service.getSavedScooterIds(),
            builder: (context, ids) {
              return ListTile(
                title: Text(FlutterI18n.translate(context, "stats_scooter_id")),
                subtitle: Text(ids.data?.first ??
                    FlutterI18n.translate(context, "stats_unknown")),
              );
            }),
        if (widget.service.autoUnlock)
          StreamBuilder<int?>(
            stream: widget.service.rssi,
            builder: (context, snapshot) {
              return ListTile(
                title: Text(FlutterI18n.translate(context, "stats_rssi")),
                subtitle: Text(snapshot.data != null
                    ? "${snapshot.data} dBm"
                    : FlutterI18n.translate(
                        context, "stats_rssi_disconnected")),
              );
            },
          ),
        StreamBuilder<LatLng?>(
            stream: widget.service.lastLocation,
            builder: (context, position) {
              return FutureBuilder<String?>(
                  future: GeoHelper.getAddress(position.data),
                  builder: (context, address) {
                    return ListTile(
                      title: Text(FlutterI18n.translate(
                          context, "stats_last_seen_near")),
                      subtitle: Text(address.hasData
                          ? address.data!
                          : FlutterI18n.translate(context, "stats_unknown")),
                      trailing: position.hasData
                          ? const Icon(Icons.exit_to_app_outlined)
                          : null,
                      onTap: position.hasData
                          ? () {
                              MapsLauncher.launchCoordinates(
                                  position.data!.latitude,
                                  position.data!.longitude);
                            }
                          : null,
                    );
                  });
            }),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            height: 300,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: StreamBuilder<LatLng?>(
                stream: widget.service.lastLocation,
                builder: (context, lastLocationSnap) {
                  if (!lastLocationSnap.hasData) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_disabled, size: 32),
                          const SizedBox(height: 16),
                          Text(
                            FlutterI18n.translate(context, "stats_no_location"),
                          ),
                        ],
                      ),
                    );
                  }
                  log("Location: ${lastLocationSnap.data.toString()}");
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: FlutterMap(
                      options: MapOptions(
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.pinchZoom,
                        ),
                        initialZoom: 16,
                        initialCenter: lastLocationSnap.data!,
                      ),
                      children: [
                        TileLayer(
                          retinaMode: true,
                          urlTemplate:
                              'https://tiles-eu.stadiamaps.com/tiles/alidade_smooth${context.isDarkMode ? "_dark" : ""}/{z}/{x}/{y}{r}.png?api_key=${const String.fromEnvironment("STADIA_TOKEN")}',
                          userAgentPackageName: 'de.freal.unustasis',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: lastLocationSnap.data!,
                              width: 40,
                              height: 40,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.dataIsOld
                                      ? Colors.grey
                                      : (Theme.of(context).colorScheme.primary
                                              as MaterialColor)
                                          .shade600,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.moped_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const RichAttributionWidget(attributions: [
                          TextSourceAttribution("Stadia Maps"),
                          TextSourceAttribution("OpenStreetMaps contributors"),
                        ])
                      ],
                    ),
                  );
                }),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }
}
