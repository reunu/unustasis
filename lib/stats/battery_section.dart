import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import '../scooter_service.dart';

class BatterySection extends StatefulWidget {
  const BatterySection(
      {required this.service, required this.dataIsOld, super.key});
  final bool dataIsOld;
  final ScooterService service;

  @override
  State<BatterySection> createState() => _BatterySectionState();
}

class _BatterySectionState extends State<BatterySection> {
  final log = Logger("BatterySection");
  bool nfcScanning = false;
  int? nfcBattery;
  int? nfcCycles;
  bool showNfcNotice = false;

  late int _primaryRange;
  late int _secondaryRange;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int?>(
        stream: widget.service.secondarySOC,
        builder: (context, secondarySOCSnap) {
          _secondaryRange = secondarySOCSnap.hasData
              ? (45 * (secondarySOCSnap.data! / 100)).round()
              : 0;
          return StreamBuilder<int?>(
              stream: widget.service.primarySOC,
              builder: (context, primarySOCSnap) {
                _primaryRange = primarySOCSnap.hasData
                    ? (45 * (primarySOCSnap.data! / 100)).round()
                    : 0;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32.0),
                      child: Column(
                        children: [
                          Text(
                            "${_primaryRange + _secondaryRange} km ${FlutterI18n.translate(context, "stats_total_range")}",
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (_primaryRange == 0 && _secondaryRange == 0)
                                ? FlutterI18n.translate(
                                    context, "stats_no_batteries")
                                : FlutterI18n.translate(
                                    context, "stats_range_until_throttled",
                                    translationParams: {
                                        "range":
                                            "${math.max(0, _primaryRange - 9) + math.max(0, _secondaryRange - 9)}"
                                      }),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        if (secondarySOCSnap.hasData &&
                            secondarySOCSnap.data! > 0)
                          Expanded(
                            child: LinearProgressIndicator(
                              value: secondarySOCSnap.data! / 100,
                              borderRadius: BorderRadius.circular(16.0),
                              minHeight: 24,
                              backgroundColor:
                                  Theme.of(context).colorScheme.surface,
                              color: widget.dataIsOld
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.4)
                                  : primarySOCSnap.data! <= 15
                                      ? Colors.red
                                      : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        if (secondarySOCSnap.hasData &&
                            secondarySOCSnap.data! > 0)
                          const SizedBox(width: 8),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: (primarySOCSnap.data ?? 0) / 100,
                            borderRadius: BorderRadius.circular(16.0),
                            minHeight: 24,
                            backgroundColor:
                                Theme.of(context).colorScheme.surface,
                            color: widget.dataIsOld
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.4)
                                : (primarySOCSnap.data ?? 0) <= 15
                                    ? Colors.red
                                    : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    if (primarySOCSnap.hasData && primarySOCSnap.data! > 0)
                      StreamBuilder<int?>(
                          stream: widget.service.primaryCycles,
                          builder: (context, primaryCycleSnap) {
                            return _batteryCard(
                              type: BatteryType.primary,
                              soc: primarySOCSnap.data!,
                              range: _primaryRange,
                              cycles: primaryCycleSnap.data,
                              old: widget.dataIsOld,
                            );
                          }),
                    if (secondarySOCSnap.hasData && secondarySOCSnap.data! > 0)
                      StreamBuilder<int?>(
                          stream: widget.service.secondaryCycles,
                          builder: (context, secondaryCycleSnap) {
                            return _batteryCard(
                              type: BatteryType.secondary,
                              soc: secondarySOCSnap.data!,
                              range: _secondaryRange,
                              cycles: secondaryCycleSnap.data,
                              old: widget.dataIsOld,
                            );
                          }),
                    Row(
                      children: [
                        Expanded(
                          child: StreamBuilder<int?>(
                            stream: widget.service.cbbSOC,
                            builder: (context, snapshot) {
                              return StreamBuilder<bool?>(
                                  stream: widget.service.cbbCharging,
                                  builder: (context, cbbCharging) {
                                    return _internalBatteryCard(
                                      type: BatteryType.cbb,
                                      soc: snapshot.data ?? 100,
                                      charging: cbbCharging.data,
                                      old: widget.dataIsOld,
                                    );
                                  });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StreamBuilder<int?>(
                            stream: widget.service.auxSOC,
                            builder: (context, snapshot) {
                              return _internalBatteryCard(
                                type: BatteryType.aux,
                                soc: snapshot.data ?? 100,
                                old: widget.dataIsOld,
                              );
                            },
                          ),
                        ),
                      ],
                    ),

                    // only available on Android, hidden right now though
                    if (Platform.isWindows)
                      Divider(
                        height: 40,
                        indent: 0,
                        endIndent: 0,
                        color: Theme.of(context)
                            .colorScheme
                            .onBackground
                            .withOpacity(0.1),
                      ),
                    if (nfcBattery != 0 && nfcBattery != null && !nfcScanning)
                      _batteryCard(
                        type: BatteryType.nfc,
                        soc: nfcBattery ?? 0,
                        range: (nfcBattery != null)
                            ? (nfcBattery! * 0.45).round()
                            : 0,
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
                                  FlutterI18n.translate(
                                      context, "stats_nfc_instructions"),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                if (showNfcNotice)
                                  Text(
                                    FlutterI18n.translate(
                                        context, "stats_nfc_notice"),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            ))
                        : (Platform.isWindows)
                            // hiding until it works
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(60),
                                    side: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onBackground,
                                    ),
                                  ),
                                  onPressed: () async {
                                    // Check availability
                                    if (await NfcManager.instance
                                            .isAvailable() ==
                                        false) {
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
                                        log.severe("NFC Error!", error.message);
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
                                                    context,
                                                    "stats_nfc_invalid"),
                                              );
                                              return;
                                            }
                                            socData = await mifare.readPages(
                                                pageOffset: 23);
                                            cycleData = await mifare.readPages(
                                                pageOffset: 20);
                                          } else {
                                            return;
                                          }

                                          // Parse data
                                          log.info(
                                              "SOC Hex: ${socData.map((e) => e.toRadixString(16))}");
                                          int fullCap =
                                              33000; //(socData[5] << 8) + socData[4];
                                          int remainingCap =
                                              (socData[3] << 8) + socData[1];
                                          int cycles = cycleData[0] - 1;
                                          log.info("Remaining: $remainingCap");
                                          log.info("Full: $fullCap");
                                          log.info("Cycles: $cycles");
                                          setState(() {
                                            nfcBattery =
                                                (remainingCap / fullCap * 100)
                                                    .round();
                                            nfcCycles = cycles;
                                          });
                                        } catch (e, stack) {
                                          log.severe(
                                              "Error reading NFC", e, stack);
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
                                    FlutterI18n.translate(
                                        context, "stats_nfc_button"),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onBackground,
                                    ),
                                  ),
                                ),
                              )
                            : Container(),
                  ],
                );
              });
        });
  }

  Widget _internalBatteryCard({
    required BatteryType type,
    required int soc,
    bool? charging,
    bool old = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 180,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
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
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 24),
              child: Text(
                type.socText(soc, context),
                style: Theme.of(context).textTheme.displaySmall,
                textScaler: TextScaler.noScaling,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Image.asset(
                width: double.infinity,
                type.imagePath(soc),
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _batteryCard({
    required BatteryType type,
    required int soc,
    required int range,
    int? cycles,
    bool old = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 160,
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
                  const SizedBox(height: 32),
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
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (cycles != null)
                        const Icon(
                          Icons.refresh,
                          size: 16,
                        ),
                      const SizedBox(width: 4),
                      if (cycles != null) Text(cycles.toString()),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.navigation_outlined,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text("$range km")
                    ],
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
        return "images/battery/batt_internal.webp";
      case BatteryType.aux:
        return 'images/battery/batt_internal.webp';
    }
  }
}
