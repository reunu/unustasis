import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:unustasis/scooter_service.dart';

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
        const Divider(
          height: 40,
          indent: 12,
          endIndent: 12,
          color: Colors.white24,
        ),
        nfcBattery != 0 && nfcBattery != null && !nfcScanning
            ? _batteryCard(
                type: BatteryType.nfc,
                soc: nfcBattery ?? 0,
                cycles: nfcCycles,
                old: false,
              )
            : Container(),
        nfcScanning
            ? Padding(
                padding: const EdgeInsets.all(16),
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
                    showNfcNotice
                        ? Text(
                            FlutterI18n.translate(context, "stats_nfc_notice"),
                            textAlign: TextAlign.center,
                          )
                        : Container(),
                  ],
                ))
            : Platform.isAndroid
                // only show the NFC tool on android for now
                // TODO iOS implementation
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(60),
                        side: const BorderSide(
                          color: Colors.white,
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
                              if (Platform.isAndroid) {
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
                                // NOT AVAILABLE ON iOS YET
                                return;
                              }

                              // Parse data
                              int remainingCap = (socData[3] << 8) + socData[2];
                              int cycles = cycleData[0];
                              log("Remaining: $remainingCap");
                              log("Cycles: $cycles");
                              setState(() {
                                nfcBattery =
                                    (remainingCap / 33000 * 100).round();
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
                        style: const TextStyle(
                          color: Colors.white,
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
        height: 180,
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.background,
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
                      : Container(),
                  type == BatteryType.cbb
                      ? charging != null
                          ? Text(FlutterI18n.translate(
                              context,
                              charging
                                  ? "stats_cbb_charging"
                                  : "stats_cbb_not_charging"))
                          : const Text("   ")
                      : Container(),
                  type == BatteryType.aux ? const Text("    ") : Container(),
                  SizedBox(
                      height:
                          (type == BatteryType.aux || type == BatteryType.cbb)
                              ? 48
                              : 16),
                  Expanded(
                    child: Image.asset(
                      type.imagePath(soc),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    type.description(context),
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
                    "$soc%",
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 12.0),
                  LinearProgressIndicator(
                    value: soc / 100,
                    borderRadius: BorderRadius.circular(16.0),
                    minHeight: 16,
                    backgroundColor: Colors.black.withOpacity(0.5),
                    color: old
                        ? Theme.of(context).colorScheme.surface
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
