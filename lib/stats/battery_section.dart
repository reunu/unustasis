import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:unu_app/scooter_service.dart';

class BatterySection extends StatefulWidget {
  const BatterySection(
      {required this.service, required this.dataIsOld, super.key});
  final bool dataIsOld;
  final ScooterService service;

  @override
  State<BatterySection> createState() => _BatterySectionState();
}

class _BatterySectionState extends State<BatterySection> {
  bool nfcScanning = false;
  int? nfcBattery;
  int? nfcCycles;
  bool showNfcNotice = false;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      children: [
        StreamBuilder<int?>(
          stream: widget.service.primarySOC,
          builder: (context, socSnap) {
            return StreamBuilder<int?>(
                stream: widget.service.primaryCycles,
                builder: (context, cycleSnap) {
                  return _batteryCard(
                    type: BatteryType.primary,
                    soc: socSnap.data ?? 0,
                    cycles: cycleSnap.data,
                    old: widget.dataIsOld,
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
                  return _batteryCard(
                    type: BatteryType.secondary,
                    soc: socSnap.data ?? 0,
                    cycles: cycleSnap.data,
                    old: widget.dataIsOld,
                  );
                });
          },
        ),
        StreamBuilder<int?>(
          stream: widget.service.cbbSOC,
          builder: (context, snapshot) {
            return StreamBuilder<bool?>(
                stream: widget.service.cbbCharging,
                builder: (context, cbbCharging) {
                  return _batteryCard(
                    type: BatteryType.cbb,
                    soc: snapshot.data ?? 0,
                    charging: cbbCharging.data,
                    old: widget.dataIsOld,
                  );
                });
          },
        ),
        StreamBuilder<int?>(
          stream: widget.service.auxSOC,
          builder: (context, snapshot) {
            return _batteryCard(
              type: BatteryType.aux,
              soc: snapshot.data ?? 0,
              old: widget.dataIsOld,
            );
          },
        ),
        // only available on Android, hidden right now though
        if (Platform.isWindows)
          Divider(
            height: 40,
            indent: 0,
            endIndent: 0,
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.1),
          ),
        if (nfcBattery != 0 && nfcBattery != null && !nfcScanning)
          _batteryCard(
            type: BatteryType.nfc,
            soc: nfcBattery ?? 0,
            cycles: nfcCycles,
            old: false,
          ),
        nfcScanning
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      FlutterI18n.translate(context, "stats_nfc_instructions"),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (showNfcNotice)
                      Text(
                        FlutterI18n.translate(context, "stats_nfc_notice"),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ))
            : (Platform.isWindows)
                // hiding until it works
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(60),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.onBackground,
                        ),
                      ),
                      onPressed: () async {
                        // Check availability
                        if (await NfcManager.instance.isAvailable() == false) {
                          Fluttertoast.showToast(
                            msg: FlutterI18n.translate(
                                context, "stats_nfc_not_available"),
                          );
                          setState(() {
                            nfcScanning = false;
                          });
                          return;
                        }
                        setState(() {
                          nfcScanning = true;
                          showNfcNotice = false;
                        });
                        Timer noticeTimer =
                            Timer(const Duration(seconds: 8), () {
                          setState(() {
                            showNfcNotice = true;
                          });
                        });
                        // Start Session
                        NfcManager.instance.startSession(
                          onError: (error) {
                            log("NFC Error: ${error.message}");
                            Fluttertoast.showToast(
                              msg: FlutterI18n.translate(
                                  context, "stats_nfc_error"),
                            );
                            setState(() {
                              nfcScanning = false;
                              showNfcNotice = false;
                            });
                            throw error;
                          },
                          onDiscovered: (NfcTag tag) async {
                            noticeTimer.cancel();
                            setState(() {
                              nfcScanning = false;
                              nfcBattery = null;
                              nfcCycles = null;
                              showNfcNotice = false;
                            });
                            try {
                              Uint8List socData;
                              Uint8List cycleData;
                              // Read from battery
                              if (Platform.isWindows) {
                                MifareUltralight? mifare =
                                    MifareUltralight.from(tag);
                                if (mifare == null) {
                                  Fluttertoast.showToast(
                                    msg: FlutterI18n.translate(
                                        context, "stats_nfc_invalid"),
                                  );
                                  return;
                                }
                                socData =
                                    await mifare.readPages(pageOffset: 23);
                                cycleData =
                                    await mifare.readPages(pageOffset: 20);
                              } else {
                                return;
                              }

                              // Parse data
                              log("SOC Hex: ${socData.map((e) => e.toRadixString(16))}");
                              int fullCap =
                                  33000; //(socData[5] << 8) + socData[4];
                              int remainingCap = (socData[3] << 8) + socData[1];
                              int cycles = cycleData[0] - 1;
                              log("Remaining: $remainingCap");
                              log("Full: $fullCap");
                              log("Cycles: $cycles");
                              setState(() {
                                nfcBattery =
                                    (remainingCap / fullCap * 100).round();
                                nfcCycles = cycles;
                              });
                            } catch (e) {
                              log("Error reading NFC: $e");
                              Fluttertoast.showToast(
                                msg: "Error reading NFC",
                              );
                            }
                            // We have our data, stop session
                            NfcManager.instance.stopSession();
                          },
                        );
                      },
                      child: Text(
                        FlutterI18n.translate(context, "stats_nfc_button"),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onBackground,
                        ),
                      ),
                    ),
                  )
                : Container(),
      ],
    );
  }

  Widget _batteryCard({
    required BatteryType type,
    required int soc,
    int? cycles,
    bool? charging,
    bool old = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: (type == BatteryType.primary ||
                type == BatteryType.secondary ||
                type == BatteryType.nfc)
            ? 180
            : 160,
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16.0),
          border: (soc <= 15 && !old)
              ? Border.all(
                  color: Colors.red,
                  width: 2,
                )
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.name(context).toUpperCase(),
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onBackground
                            .withOpacity(0.5)),
                  ),
                  if (type == BatteryType.primary ||
                      type == BatteryType.secondary ||
                      type == BatteryType.nfc)
                    (cycles != null && cycles > 0)
                        ? Row(
                            children: [
                              const Icon(
                                Icons.refresh,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                FlutterI18n.translate(context, "stats_cycles",
                                    translationParams: {
                                      "cycles": cycles.toString(),
                                    }),
                              ),
                            ],
                          )
                        : const Text("   "),
                  if (type == BatteryType.cbb)
                    (charging != null)
                        ? Text(FlutterI18n.translate(
                            context,
                            charging
                                ? "stats_cbb_charging"
                                : "stats_cbb_not_charging"))
                        : const Text("   "),
                  if (type == BatteryType.aux) const Text("    "),
                  SizedBox(
                      height:
                          (type == BatteryType.aux || type == BatteryType.cbb)
                              ? 48
                              : 16),
                  Expanded(
                    child: Image.asset(
                      type.imagePath(soc),
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16.0), // for padding
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    type.description(context),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onBackground
                            .withOpacity(0.5)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    type.socText(soc, context),
                    style: Theme.of(context).textTheme.displaySmall,
                    textScaler: TextScaler.noScaling,
                  ),
                  const SizedBox(height: 12.0),
                  type == BatteryType.aux
                      ? _splitProgressBar(
                          maxSteps: 4,
                          currentStep: soc ~/ 25,
                          context: context,
                          old: old,
                        )
                      : LinearProgressIndicator(
                          value: soc / 100,
                          borderRadius: BorderRadius.circular(16.0),
                          minHeight: 16,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .onTertiary
                              .withOpacity(0.7),
                          color: old
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.4)
                              : soc <= 15
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                        ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _splitProgressBar(
      {required int maxSteps,
      required int currentStep,
      required BuildContext context,
      required bool old}) {
    List<Widget> bars = [];
    for (int i = 0; i < maxSteps; i++) {
      bars.add(
        Expanded(
          child: Container(
            height: 16,
            decoration: BoxDecoration(
              color: i < currentStep
                  ? (old
                      ? Theme.of(context).colorScheme.onSurface.withOpacity(0.4)
                      : Theme.of(context).colorScheme.primary)
                  : Theme.of(context).colorScheme.onTertiary.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
      if (i < maxSteps - 1) {
        bars.add(const SizedBox(width: 8));
      }
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: bars,
    );
  }
}

enum BatteryType { primary, secondary, cbb, aux, nfc }

extension BatteryExtension on BatteryType {
  String name(BuildContext context) {
    switch (this) {
      case BatteryType.primary:
        return FlutterI18n.translate(context, "stats_primary_name");
      case BatteryType.secondary:
        return FlutterI18n.translate(context, "stats_secondary_name");
      case BatteryType.cbb:
        return FlutterI18n.translate(context, "stats_cbb_name");
      case BatteryType.aux:
        return FlutterI18n.translate(context, "stats_aux_name");
      case BatteryType.nfc:
        return FlutterI18n.translate(context, "stats_nfc_name");
    }
  }

  String description(BuildContext context) {
    switch (this) {
      case BatteryType.primary:
        return FlutterI18n.translate(context, "stats_primary_desc");
      case BatteryType.secondary:
        return FlutterI18n.translate(context, "stats_secondary_desc");
      case BatteryType.cbb:
        return FlutterI18n.translate(context, "stats_cbb_desc");
      case BatteryType.aux:
        return FlutterI18n.translate(context, "stats_aux_desc");
      case BatteryType.nfc:
        return FlutterI18n.translate(context, "stats_nfc_desc");
    }
  }

  String socText(int soc, BuildContext context) {
    if (this == BatteryType.aux) {
      switch (soc ~/ 25) {
        case 0:
          return FlutterI18n.translate(context, "stats_aux_0");
        case 1:
          return FlutterI18n.translate(context, "stats_aux_25");
        case 2:
          return FlutterI18n.translate(context, "stats_aux_50");
        case 3:
          return FlutterI18n.translate(context, "stats_aux_75");
        case 4:
          return FlutterI18n.translate(context, "stats_aux_100");
      }
    }
    return "$soc%";
  }

  String imagePath(int soc) {
    switch (this) {
      case BatteryType.primary:
      case BatteryType.secondary:
      case BatteryType.nfc:
        if (soc > 85) {
          return "images/battery/batt_full.webp";
        } else if (soc > 60) {
          return "images/battery/batt_75.webp";
        } else if (soc > 35) {
          return "images/battery/batt_50.webp";
        } else if (soc > 10) {
          return "images/battery/batt_25.webp";
        } else {
          return "images/battery/batt_empty.webp";
        }
      case BatteryType.cbb:
        return "images/battery/batt_cbb.webp";
      case BatteryType.aux:
        return 'images/battery/batt_aux.webp';
    }
  }
}
