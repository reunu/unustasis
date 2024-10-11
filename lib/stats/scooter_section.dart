import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../stats/stats_screen.dart';
import '../onboarding_screen.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_state.dart';
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

  List<SavedScooter> sortedScooters() {
    List<SavedScooter> scooters = widget.service.savedScooters.values.toList();
    scooters.sort((a, b) {
      // Check if either scooter is the connected one
      if (a.id == widget.service.myScooter?.remoteId.toString()) return -1;
      if (b.id == widget.service.myScooter?.remoteId.toString()) return 1;

      // If neither is the connected scooter, sort by lastPing
      return b.lastPing.compareTo(a.lastPing);
    });
    return scooters;
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
              ...sortedScooters().map((scooter) {
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
                    if (widget.service.myScooter != null) {
                      widget.service.myScooter!.disconnect();
                      widget.service.myScooter = null;
                    }
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
                    color: Theme.of(context).colorScheme.surface,
                    size: 16,
                  ),
                  label: Text(
                    FlutterI18n.translate(context, "settings_add_scooter")
                        .toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                  ),
                ),
              ),
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
  final log = Logger("ScooterSection");
  final bool connected;
  final SavedScooter savedScooter;
  final ScooterService service;
  final void Function() rebuild;
  SavedScooterCard({
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
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      child: FutureBuilder<SharedPreferences>(
          future: SharedPreferences.getInstance(),
          builder: (context, snapshot) {
            bool showOnboarding =
                snapshot.data?.getBool("color_onboarded") != true;
            return Column(
              children: [
                const SizedBox(height: 4),
                GestureDetector(
                  child: Image.asset(
                    "images/scooter/side_${savedScooter.color}.webp",
                    height: 160,
                  ),
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    int? newColor = await showColorDialog(
                        savedScooter.color, savedScooter.name, context);
                    if (newColor != null) {
                      savedScooter.color = newColor;
                      rebuild();
                    }
                    if (showOnboarding && snapshot.hasData) {
                      snapshot.data!.setBool("color_onboarded", true);
                      rebuild();
                    }
                  },
                ),
                if (showOnboarding)
                  Text(
                    FlutterI18n.translate(context, "settings_color_onboarding"),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5),
                        ),
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
                      service.renameSavedScooter(
                          name: newName, id: savedScooter.id);
                      rebuild();
                    }
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? FlutterI18n.translate(context, "state_name_unknown")
                      : FlutterI18n.translate(
                          context, "state_name_disconnected"),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                if (connected)
                  Divider(
                    indent: 16,
                    endIndent: 16,
                    height: 0,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.1),
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
                if (!connected)
                  Divider(
                    indent: 16,
                    endIndent: 16,
                    height: 0,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.1),
                  ),
                if (!connected)
                  ListTile(
                    title: Text(FlutterI18n.translate(
                        context, "stats_last_ping_title")),
                    subtitle: Text(FlutterI18n.translate(
                        context, "stats_last_ping",
                        translationParams: {
                          "time": savedScooter.lastPing
                              .calculateTimeDifferenceInShort(context)
                              .toLowerCase()
                        })),
                    onTap: () {
                      Fluttertoast.showToast(
                          msg: savedScooter.lastPing
                              .toString()
                              .substring(0, 16));
                    },
                  ),
                if (savedScooter.lastLocation != null && !connected)
                  Divider(
                    indent: 16,
                    endIndent: 16,
                    height: 0,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.1),
                  ),
                if (savedScooter.lastLocation != null && !connected)
                  ListTile(
                    title: Text(
                      FlutterI18n.translate(context, "stats_last_seen_near"),
                    ),
                    subtitle: FutureBuilder<String?>(
                      future: GeoHelper.getAddress(
                          savedScooter.lastLocation!, context),
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
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                ),
                ListTile(
                  title: Text("ID"),
                  subtitle: Text(savedScooter.id),
                ),
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      if (connected)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                          ),
                          onPressed: () async {
                            service.stopAutoRestart();
                            service.myScooter?.disconnect();
                            service.myScooter = null;
                            rebuild();
                          },
                          icon: const Icon(
                            Icons.close_outlined,
                            size: 16,
                          ),
                          label: Text(
                            FlutterI18n.translate(
                                    context, "settings_disconnect")
                                .toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      if (!connected)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                          ),
                          onPressed: () async {
                            try {
                              log.info(
                                  "Trying to connect to ${savedScooter.id}");
                              await service.connectToScooterId(savedScooter.id);
                              service.startAutoRestart();
                              rebuild();
                            } catch (e, stack) {
                              log.severe(
                                  "Couldn't connect to ${savedScooter.id}",
                                  e,
                                  stack);
                              Fluttertoast.showToast(
                                  msg: FlutterI18n.translate(
                                      context, "settings_connect_failed",
                                      translationParams: {
                                    "name": savedScooter.name
                                  }));
                            }
                          },
                          icon: const Icon(
                            Icons.bluetooth,
                            size: 16,
                          ),
                          label: Text(
                            FlutterI18n.translate(context, "settings_connect")
                                .toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
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
                            ));
                          }
                        },
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 16,
                        ),
                        label: Text(
                          FlutterI18n.translate(context, "settings_forget")
                              .toUpperCase(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
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

  Future<int?> showColorDialog(
      int initialValue, String scooterName, BuildContext context) {
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
                  if (scooterName == magic("Rpyvcfr"))
                    _colorRadioTile(
                      colorName: "eclipse",
                      colorValue: 7,
                      color: Colors.grey.shade800,
                      selectedValue: selectedValue,
                      onChanged: (value) {
                        setState(() {
                          selectedValue = value!;
                        });
                      },
                      context: context,
                    ),
                  if (scooterName == magic("Xbev"))
                    _colorRadioTile(
                      colorName: "idioteque",
                      colorValue: 8,
                      color: Colors.teal.shade200,
                      selectedValue: selectedValue,
                      onChanged: (value) {
                        setState(() {
                          selectedValue = value!;
                        });
                      },
                      context: context,
                    ),
                  if (scooterName == magic("Ubire"))
                    _colorRadioTile(
                      colorName: "hover",
                      colorValue: 9,
                      color: Colors.lightBlue,
                      selectedValue: selectedValue,
                      onChanged: (value) {
                        setState(() {
                          selectedValue = value!;
                        });
                      },
                      context: context,
                    )
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

  String magic(String input) {
    return input.split('').map((char) {
      if (RegExp(r'[a-z]').hasMatch(char)) {
        return String.fromCharCode(((char.codeUnitAt(0) - 97 + 13) % 26) + 97);
      } else if (RegExp(r'[A-Z]').hasMatch(char)) {
        return String.fromCharCode(((char.codeUnitAt(0) - 65 + 13) % 26) + 65);
      } else {
        return char;
      }
    }).join('');
  }
}
