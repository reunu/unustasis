import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/home_screen.dart';

import '../stats/stats_screen.dart';
import '../onboarding_screen.dart';
import '../domain/saved_scooter.dart';
import '../domain/scooter_state.dart';
import '../geo_helper.dart';
import '../scooter_service.dart';

class ScooterSection extends StatefulWidget {
  const ScooterSection({
    super.key,
    this.onNavigateBack,
  });

  final VoidCallback? onNavigateBack;

  @override
  State<ScooterSection> createState() => _ScooterSectionState();
}

class _ScooterSectionState extends State<ScooterSection> {
  int color = 1;
  String? nameCache;
  TextEditingController nameController = TextEditingController();
  FocusNode nameFocusNode = FocusNode();

  void setupInitialColor() async {
    int initialColor = await SharedPreferencesAsync().getInt("color") ?? 1;
    setState(() {
      color = initialColor;
    });
  }

  @override
  void initState() {
    super.initState();
    setupInitialColor();
  }

  List<SavedScooter> sortedScooters(BuildContext context) {
    List<SavedScooter> scooters =
        context.read<ScooterService>().savedScooters.values.toList();
    scooters.sort((a, b) {
      // Check if either scooter is the connected one
      if (a.id ==
          context.read<ScooterService>().myScooter?.remoteId.toString()) {
        return -1;
      }
      if (b.id ==
          context.read<ScooterService>().myScooter?.remoteId.toString()) {
        return 1;
      }

      // If neither is the connected scooter, sort by lastPing
      return b.lastPing.compareTo(a.lastPing);
    });
    return scooters;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shrinkWrap: true,
      children: [
        ...sortedScooters(context).map((scooter) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: SavedScooterCard(
              savedScooter: scooter,
              single: sortedScooters(context).length == 1,
              connected: (scooter.id ==
                      context
                          .read<ScooterService>()
                          .myScooter
                          ?.remoteId
                          .toString() &&
                  context.select<ScooterService, ScooterState?>(
                          (service) => service.state) !=
                      ScooterState.disconnected),
              rebuild: () => setState(() {}),
              onNavigateBack: widget.onNavigateBack,
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              backgroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () async {
              ScooterService service = context.read<ScooterService>();
              service.myScooter?.disconnect();
              service.myScooter = null;

              List<String> savedIds = await service.getSavedScooterIds();
              if (context.mounted) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) {
                    return OnboardingScreen(
                      excludedScooterIds: savedIds,
                      skipWelcome: true,
                    );
                  },
                ));
              }
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
  final bool single;
  final void Function() rebuild;
  final VoidCallback? onNavigateBack;
  SavedScooterCard({
    super.key,
    required this.savedScooter,
    required this.connected,
    required this.single,
    required this.rebuild,
    this.onNavigateBack,
  });

  void setColor(int newColor, BuildContext context) async {
    savedScooter.color = newColor;
    SharedPreferencesAsync prefs = SharedPreferencesAsync();
    await prefs.setInt("color", newColor);
    if (context.mounted) context.read<ScooterService>().scooterColor = newColor;
  }

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
            // Check for april fools
            bool forceHover = snapshot.data?.getBool("seasonal") == true &&
                DateTime.now().month == 4 &&
                DateTime.now().day == 1;
            return Column(
              children: [
                const SizedBox(height: 4),
                GestureDetector(
                  child: Image.asset(
                    "images/scooter/side_${forceHover ? 9 : savedScooter.color}.webp",
                    height: 160,
                  ),
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    int? newColor = await showColorDialog(
                        savedScooter.color, savedScooter.name, context);
                    if (newColor != null && context.mounted) {
                      setColor(newColor, context);
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
                              .withValues(alpha: 0.5),
                        ),
                  ),
                const SizedBox(height: 4),
                // Scooter name and edit button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
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
                          newName != savedScooter.name &&
                          context.mounted) {
                        context.read<ScooterService>().renameSavedScooter(
                            name: newName, id: savedScooter.id);
                        rebuild();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 2),
                // Scooter state or last ping
                connected
                    ? Text(
                        context
                                .select<ScooterService, ScooterState?>(
                                    (service) => service.state)
                                ?.description(context) ??
                            FlutterI18n.translate(context, "stats_unknown"),
                        style: Theme.of(context).textTheme.titleMedium,
                      )
                    : Text(
                        FlutterI18n.translate(context, "stats_last_ping_toast",
                            translationParams: {
                              "time": savedScooter.lastPing
                                  .calculateTimeDifferenceInShort(context)
                                  .toLowerCase()
                            }),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                SizedBox(height: 12),
                BatteryBars(
                  primarySOC: savedScooter.lastPrimarySOC,
                  secondarySOC: savedScooter.lastSecondarySOC,
                  dataIsOld: savedScooter.dataIsOld,
                ),
                const SizedBox(height: 24),
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.1),
                ),
                if (savedScooter.lastLocation != null && !connected)
                  Divider(
                    indent: 16,
                    endIndent: 16,
                    height: 0,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.1),
                  ),
                if (savedScooter.lastLocation != null && !connected)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.1),
                ),
                if (!single) // only show this if there's more than one scooter
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(FlutterI18n.translate(
                        context, "stats_scooter_auto_connect")),
                    subtitle: Text(savedScooter.autoConnect
                        ? FlutterI18n.translate(context,
                            "stats_scooter_auto_connect_on_description")
                        : FlutterI18n.translate(context,
                            "stats_scooter_auto_connect_off_description")),
                    trailing: Switch(
                      value: savedScooter.autoConnect,
                      onChanged: (value) {
                        savedScooter.autoConnect = value;
                        rebuild();
                      },
                    ),
                  ),
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.1),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text("ID"),
                  subtitle: Text(
                    savedScooter.id,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Divider(
                  indent: 16,
                  endIndent: 16,
                  height: 0,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.1),
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
                            ScooterService service =
                                context.read<ScooterService>();
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

                              // Start the connection but don't wait for it to fully complete
                              // Just initiate it and navigate back immediately
                              context
                                  .read<ScooterService>()
                                  .connectToScooterId(savedScooter.id);

                              if (context.mounted) {
                                context
                                    .read<ScooterService>()
                                    .startAutoRestart();
                                rebuild();
                                // Navigate back to main screen after initiating connection
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  onNavigateBack?.call();
                                });
                              }
                            } catch (e, stack) {
                              log.severe(
                                  "Couldn't connect to ${savedScooter.id}",
                                  e,
                                  stack);
                              if (context.mounted) {
                                Fluttertoast.showToast(
                                    msg: FlutterI18n.translate(
                                        (context), "settings_connect_failed",
                                        translationParams: {
                                      "name": savedScooter.name
                                    }));
                              }
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
                          if (forget == true && context.mounted) {
                            String name = savedScooter.name;
                            context
                                .read<ScooterService>()
                                .forgetSavedScooter(savedScooter.id);
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
          if (context.mounted) {
            FocusScope.of(context).requestFocus(textFieldNode);
          }
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
