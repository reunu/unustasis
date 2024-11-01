import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:provider/provider.dart';

import '../domain/scooter_battery.dart';
import '../scooter_service.dart';

class BatterySection extends StatefulWidget {
  const BatterySection({required this.dataIsOld, super.key});

  final bool dataIsOld;

  @override
  State<BatterySection> createState() => _BatterySectionState();
}

class _BatterySectionState extends State<BatterySection> {
  final log = Logger("BatterySection");
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
        Selector<ScooterService, ({int? primarySOC, int? secondarySOC})>(
            selector: (context, service) => (
                  primarySOC: service.primarySOC,
                  secondarySOC: service.secondarySOC
                ),
            builder: (context, data, _) {
              int primaryRange = data.primarySOC != null
                  ? (45 * (data.primarySOC! / 100)).round()
                  : 0;
              int secondaryRange = data.secondarySOC != null
                  ? (45 * (data.secondarySOC! / 100)).round()
                  : 0;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32.0),
                  child: Column(
                    children: [
                      Text(
                        "${primaryRange + secondaryRange} km ${FlutterI18n.translate(context, "stats_total_range")}",
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (primaryRange == 0 && secondaryRange == 0)
                            ? FlutterI18n.translate(
                                context, "stats_no_batteries")
                            : FlutterI18n.translate(
                                context, "stats_range_until_throttled",
                                translationParams: {
                                    "range":
                                        "${math.max(0, primaryRange - 9) + math.max(0, secondaryRange - 9)}"
                                  }),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    if (data.secondarySOC != null && data.secondarySOC! > 0)
                      Expanded(
                        child: LinearProgressIndicator(
                          value: data.secondarySOC! / 100,
                          borderRadius: BorderRadius.circular(16.0),
                          minHeight: 24,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainer,
                          color: widget.dataIsOld
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.4)
                              : data.secondarySOC! <= 15
                                  ? Colors.red
                                  : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    if (data.secondarySOC != null && data.secondarySOC! > 0)
                      const SizedBox(width: 8),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (data.primarySOC ?? 0) / 100,
                        borderRadius: BorderRadius.circular(16.0),
                        minHeight: 24,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainer,
                        color: widget.dataIsOld
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4)
                            : (data.primarySOC ?? 0) <= 15
                                ? Colors.red
                                : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ]);
            }),
        const SizedBox(height: 32),
        if ((context.select<ScooterService, int?>(
                    (service) => service.primarySOC) ??
                0) >
            0)
          _batteryCard(
            type: ScooterBatteryType.primary,
            soc: context
                .select<ScooterService, int?>((service) => service.primarySOC)!,
            cycles: context.select<ScooterService, int?>(
                (service) => service.primaryCycles),
            old: widget.dataIsOld,
          ),

        if ((context.select<ScooterService, int?>(
                    (service) => service.secondarySOC) ??
                0) >
            0)
          _batteryCard(
            type: ScooterBatteryType.secondary,
            soc: context.select<ScooterService, int?>(
                (service) => service.secondarySOC)!,
            cycles: context.select<ScooterService, int?>(
                (service) => service.secondaryCycles),
            old: widget.dataIsOld,
          ),
        Row(
          children: [
            Expanded(
              child: _internalBatteryCard(
                type: ScooterBatteryType.cbb,
                soc: context.select<ScooterService, int?>(
                        (service) => service.cbbSOC) ??
                    100,
                charging: context.select<ScooterService, bool?>(
                    (service) => service.cbbCharging),
                old: widget.dataIsOld,
                context: context,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _internalBatteryCard(
                type: ScooterBatteryType.aux,
                soc: context.select<ScooterService, int?>(
                        (service) => service.auxSOC) ??
                    100,
                old: widget.dataIsOld,
                context: context,
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
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          ),
        if (nfcBattery != 0 && nfcBattery != null && !nfcScanning)
          _batteryCard(
            type: ScooterBatteryType.nfc,
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
                          color: Theme.of(context).colorScheme.onSurface,
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
                              log.info(
                                  "SOC Hex: ${socData.map((e) => e.toRadixString(16))}");
                              int fullCap =
                                  33000; //(socData[5] << 8) + socData[4];
                              int remainingCap = (socData[3] << 8) + socData[1];
                              int cycles = cycleData[0] - 1;
                              log.info("Remaining: $remainingCap");
                              log.info("Full: $fullCap");
                              log.info("Cycles: $cycles");
                              setState(() {
                                nfcBattery =
                                    (remainingCap / fullCap * 100).round();
                                nfcCycles = cycles;
                              });
                            } catch (e, stack) {
                              log.severe("Error reading NFC", e, stack);
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
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  )
                : Container(),
      ],
    );
  }

  Widget _internalBatteryCard({
    required ScooterBatteryType type,
    required int soc,
    bool? charging,
    bool old = false,
    required BuildContext context,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        child: Container(
          height: 180,
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
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
                        .onSurface
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
                        .onSurface
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
        onLongPress: () {
          HapticFeedback.mediumImpact();
          switch (type) {
            case ScooterBatteryType.aux:
              showDialog(
                  context: context,
                  builder: (context) => _auxDiagnosticDialog(context));
              break;
            case ScooterBatteryType.cbb:
              showDialog(
                  context: context,
                  builder: (context) => _cbbDiagnosticDialog(context));
              break;
            default:
              // no diagnostics for NFC
              break;
          }
        },
      ),
    );
  }

  AlertDialog _auxDiagnosticDialog(BuildContext context) {
    return AlertDialog(
      title: Text(
        FlutterI18n.translate(
          context,
          "stats_diagnostics_title",
          translationParams: {"type": "AUX"},
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              "SOC: ${context.select<ScooterService, int?>((service) => service.auxSOC) ?? "??? "}%"),
          Text(context
                  .select<ScooterService, AUXChargingState?>(
                      (service) => service.auxCharging)
                  ?.name(context) ??
              "???"),
          Text(
              "Voltage: ${context.select<ScooterService, int?>((service) => service.auxVoltage) ?? "??? "}mV"),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child:
              Text(FlutterI18n.translate(context, "stats_diagnostics_close")),
        ),
      ],
    );
  }

  AlertDialog _cbbDiagnosticDialog(BuildContext context) {
    return AlertDialog(
      title: Text(
        FlutterI18n.translate(
          context,
          "stats_diagnostics_title",
          translationParams: {"type": "CBB"},
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              "SOC: ${context.select<ScooterService, int?>((service) => service.cbbSOC) ?? "??? "}%"),
          Text((context.select<ScooterService, bool?>(
                      (service) => service.cbbCharging)) ==
                  true
              ? "Charging"
              : "Not charging"),
          Text(
              "Voltage: ${context.select<ScooterService, int?>((service) => service.cbbVoltage) ?? "??? "}mV"),
          Text(
              "Capacity: ${context.select<ScooterService, int?>((service) => service.cbbCapacity) ?? "??? "}mAh"),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child:
              Text(FlutterI18n.translate(context, "stats_diagnostics_close")),
        ),
      ],
    );
  }

  Widget _batteryCard({
    required ScooterBatteryType type,
    required int soc,
    int? cycles,
    bool old = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 160,
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
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
                            .onSurface
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
                            .onSurface
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
                      Text("${(45 * (soc / 100)).round()} km")
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

  // ignore: unused_element
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
