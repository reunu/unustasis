import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/onboarding_screen.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_state.dart';
import '../domain/theme_helper.dart';
import '../geo_helper.dart';
import '../scooter_service.dart';

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
    return StreamBuilder<bool>(
        stream: widget.service.connected,
        builder: (context, snapshot) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shrinkWrap: true,
            children: [
              // TODO: This needs to be refreshed automatically whenever data changes!!!
              ...widget.service.savedScooters.values.map((scooter) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: StreamBuilder<ScooterState?>(
                      stream: widget.service.state,
                      builder: (context, stateSnap) {
                        return SavedScooterCard(
                          savedScooter: scooter,
                          connected: (scooter.id ==
                                  widget.service.myScooter?.remoteId
                                      .toString() &&
                              stateSnap.data != ScooterState.disconnected),
                          service: widget.service,
                          rebuild: () => setState(() {}),
                        );
                      }),
                );
              }),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    backgroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () async {
                    List<String> savedIds =
                        await widget.service.getSavedScooterIds();
                    Navigator.push(context, MaterialPageRoute(
                      builder: (context) {
                        return OnboardingScreen(
                          service: widget.service,
                          excludedScooterIds: savedIds,
                          skipWelcome: true,
                        );
                      },
                    ));
                  },
                  icon: Icon(
                    Icons.add,
                    color: Theme.of(context).colorScheme.background,
                    size: 16,
                  ),
                  label: Text(
                    FlutterI18n.translate(context, "settings_add_scooter")
                        .toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.background,
                    ),
                  ),
                ),
              ),
              /* StreamBuilder<String?>(
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
                    subtitle: Text((ids.hasData && ids.data!.isNotEmpty)
                        ? ids.data!.first.toString()
                        : FlutterI18n.translate(context, "stats_unknown")),
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
            ),*/
            ],
          );
        });
  }

  @override
  void dispose() {
    nameController.dispose();
    nameFocusNode.dispose();
    super.dispose();
  }
}

class SavedScooterCard extends StatelessWidget {
  final bool connected;
  final SavedScooter savedScooter;
  final ScooterService service;
  final void Function() rebuild;
  const SavedScooterCard({
    super.key,
    required this.savedScooter,
    required this.connected,
    required this.service,
    required this.rebuild,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          GestureDetector(
            child: Image.asset(
              "images/scooter/side_${savedScooter.color}.webp",
              height: 160,
            ),
            onTap: () async {
              int? newColor =
                  await showColorDialog(savedScooter.color, context);
              if (newColor != null) {
                savedScooter.color = newColor;
              }
            },
          ),
          const SizedBox(height: 4),
          InkWell(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 32),
                Text(
                  savedScooter.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.edit_outlined,
                  size: 20,
                ),
              ],
            ),
            onTap: () async {
              HapticFeedback.mediumImpact();
              String? newName =
                  await showRenameDialog(savedScooter.name, context);
              if (newName != null &&
                  newName.isNotEmpty &&
                  newName != savedScooter.name) {
                service.renameSavedScooter(name: newName, id: savedScooter.id);
                rebuild();
              }
            },
          ),
          const SizedBox(height: 4),
          Text(
            connected
                ? FlutterI18n.translate(context, "state_name_unknown")
                : FlutterI18n.translate(context, "state_name_disconnected"),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          if (connected)
            Divider(
              indent: 16,
              endIndent: 16,
              height: 0,
              color:
                  Theme.of(context).colorScheme.onBackground.withOpacity(0.1),
            ),
          if (connected)
            ListTile(
              title: Text(FlutterI18n.translate(context, "stats_state")),
              subtitle: StreamBuilder<ScooterState?>(
                  stream: service.state,
                  builder: (context, state) {
                    return Text(
                      state.data?.description(context) ??
                          FlutterI18n.translate(context, "stats_unknown"),
                    );
                  }),
            ),
          if (savedScooter.lastLocation != null && !connected)
            Divider(
              indent: 16,
              endIndent: 16,
              height: 0,
              color:
                  Theme.of(context).colorScheme.onBackground.withOpacity(0.1),
            ),
          if (savedScooter.lastLocation != null && !connected)
            ListTile(
              title: Text(
                FlutterI18n.translate(context, "stats_last_seen_near"),
              ),
              subtitle: FutureBuilder<String?>(
                future: GeoHelper.getAddress(savedScooter.lastLocation!),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Text(snapshot.data!);
                  } else {
                    return Text(
                      FlutterI18n.translate(context, "stats_no_location"),
                    );
                  }
                },
              ),
              trailing: const Icon(Icons.exit_to_app_outlined),
              onTap: () {
                MapsLauncher.launchCoordinates(
                  savedScooter.lastLocation!.latitude,
                  savedScooter.lastLocation!.longitude,
                );
              },
            ),
          Divider(
            indent: 16,
            endIndent: 16,
            height: 0,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.1),
          ),
          ListTile(
            title: Text("ID"),
            subtitle: Text(savedScooter.id),
          ),
          Divider(
            indent: 16,
            endIndent: 16,
            height: 0,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                backgroundColor:
                    Theme.of(context).colorScheme.error.withOpacity(0.2),
              ),
              onPressed: () async {
                bool? forget = await showForgetDialog(context);
                if (forget == true) {
                  String name = savedScooter.name;
                  service.forgetSavedScooter(savedScooter.id);
                  rebuild();
                  Fluttertoast.showToast(
                    msg: FlutterI18n.translate(
                      context,
                      "forget_alert_success",
                      translationParams: {"name": name},
                    ),
                  );
                }
              },
              icon: Icon(
                Icons.delete_outline,
                color: HSLColor.fromColor(Theme.of(context).colorScheme.error)
                    .withLightness(context.isDarkMode ? 0.8 : 0.1)
                    .toColor(),
                size: 16,
              ),
              label: Text(
                FlutterI18n.translate(context, "settings_forget").toUpperCase(),
                style: TextStyle(
                  color: HSLColor.fromColor(Theme.of(context).colorScheme.error)
                      .withLightness(context.isDarkMode ? 0.8 : 0.1)
                      .toColor(),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> showRenameDialog(String initialValue, BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController textController =
            TextEditingController(text: initialValue);
        FocusNode textFieldNode = FocusNode();

        Future.delayed(const Duration(milliseconds: 100), () {
          FocusScope.of(context).requestFocus(textFieldNode);
        });

        return AlertDialog(
          title: Text(FlutterI18n.translate(context, "stats_name")),
          content: TextField(
            controller: textController,
            focusNode: textFieldNode,
          ),
          actions: [
            TextButton(
              child:
                  Text(FlutterI18n.translate(context, "stats_rename_cancel")),
              onPressed: () {
                Navigator.of(context).pop(); // Close without returning data
              },
            ),
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_save")),
              onPressed: () {
                Navigator.of(context)
                    .pop(textController.text); // Return the text
              },
            ),
          ],
        );
      },
    );
  }

  Future<int?> showColorDialog(int initialValue, BuildContext context) {
    int selectedValue = initialValue;

    return showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(FlutterI18n.translate(context, "settings_color")),
              const SizedBox(height: 4),
              Text(
                FlutterI18n.translate(context, "settings_color_info"),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          scrollable: true,
          content: Builder(builder: (context) {
            return StatefulBuilder(builder: (context, setState) {
              return Column(
                children: [
                  _colorRadioTile(
                    colorName: "black",
                    colorValue: 0,
                    color: Colors.black,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "white",
                    colorValue: 1,
                    color: Colors.white,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "green",
                    colorValue: 2,
                    color: Colors.green.shade900,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "gray",
                    colorValue: 3,
                    color: Colors.grey,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "orange",
                    colorValue: 4,
                    color: Colors.deepOrange.shade400,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "red",
                    colorValue: 5,
                    color: Colors.red,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                  _colorRadioTile(
                    colorName: "blue",
                    colorValue: 6,
                    color: Colors.blue,
                    selectedValue: selectedValue,
                    onChanged: (value) {
                      setState(() {
                        selectedValue = value!;
                      });
                    },
                    context: context,
                  ),
                ],
              );
            });
          }),
          actions: [
            TextButton(
              child:
                  Text(FlutterI18n.translate(context, "stats_rename_cancel")),
              onPressed: () {
                Navigator.of(context).pop(); // Close without returning data
              },
            ),
            TextButton(
              child: Text(FlutterI18n.translate(context, "stats_rename_save")),
              onPressed: () {
                Navigator.of(context).pop(selectedValue); // Return the text
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool?> showForgetDialog(BuildContext context) {
    return showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            title: Text(FlutterI18n.translate(context, "forget_alert_title")),
            content: Text(FlutterI18n.translate(context, "forget_alert_body")),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child:
                    Text(FlutterI18n.translate(context, "forget_alert_cancel")),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: Text(
                    FlutterI18n.translate(context, "forget_alert_confirm")),
              ),
            ],
          );
        });
  }

  Widget _colorRadioTile(
          {required String colorName,
          required Color color,
          required int colorValue,
          required int selectedValue,
          required void Function(int?) onChanged,
          required BuildContext context}) =>
      RadioListTile(
        contentPadding: EdgeInsets.zero,
        value: colorValue,
        groupValue: selectedValue,
        onChanged: onChanged,
        title: Text(FlutterI18n.translate(context, "color_$colorName")),
        secondary: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(
                  color: Colors.grey.shade500,
                  width: 1,
                  strokeAlign: BorderSide.strokeAlignOutside),
            ),
          ),
        ),
      );
}
