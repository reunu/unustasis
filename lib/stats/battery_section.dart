import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:logging/logging.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
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
                                  .withValues(alpha: 0.4)
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
                                .withValues(alpha: 0.4)
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
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
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
                        if (await NfcManager.instance.isAvailable() == false &&
                            context.mounted) {
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
                          pollingOptions: {NfcPollingOption.iso14443},
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
                                var mifare = MifareUltralightAndroid.from(tag);
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
                        .withValues(alpha: 0.5)),
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
                        .withValues(alpha: 0.5)),
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
    int? auxSOC =
        context.select<ScooterService, int?>((service) => service.auxSOC);
    AUXChargingState? auxCharging =
        context.select<ScooterService, AUXChargingState?>(
            (service) => service.auxCharging);
    int? auxVoltage =
        context.select<ScooterService, int?>((service) => service.auxVoltage);
    DateTime? lastPing = context
        .select<ScooterService, DateTime?>((service) => service.lastPing);

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
          Text("SOC: ${auxSOC ?? "Unknown"}%"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_charging_state")}: ${auxCharging?.name(context) ?? "Unknown "}"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_voltage")}: ${auxVoltage ?? "Unknown "}mV"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_type")}: ${FlutterI18n.translate(context, "stats_aux_desc")}"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_last_update")}: ${lastPing?.toString().split('.').first ?? "Never"}"),
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
    int? cbbSOC =
        context.select<ScooterService, int?>((service) => service.cbbSOC);
    bool? cbbCharging =
        context.select<ScooterService, bool?>((service) => service.cbbCharging);
    int? cbbVoltage =
        context.select<ScooterService, int?>((service) => service.cbbVoltage);
    int? cbbCapacity =
        context.select<ScooterService, int?>((service) => service.cbbCapacity);
    DateTime? lastPing = context
        .select<ScooterService, DateTime?>((service) => service.lastPing);

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
          Text("SOC: ${cbbSOC ?? "Unknown"}%"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_charging_state")}: ${cbbCharging == true ? "Charging" : cbbCharging == false ? "Not charging" : "Unknown"}"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_voltage")}: ${cbbVoltage ?? "Unknown "}mV"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_capacity")}: ${cbbCapacity ?? "Unknown "}mAh"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_type")}: ${FlutterI18n.translate(context, "stats_cbb_desc")}"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_last_update")}: ${lastPing?.toString().split('.').first ?? "Never"}"),
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
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          switch (type) {
            case ScooterBatteryType.primary:
            case ScooterBatteryType.secondary:
              showDialog(
                  context: context,
                  builder: (context) =>
                      _mainBatteryDiagnosticDialog(context, type, soc, cycles));
              break;
            case ScooterBatteryType.nfc:
              showDialog(
                  context: context,
                  builder: (context) =>
                      _nfcBatteryDiagnosticDialog(context, soc, cycles));
              break;
            default:
              break;
          }
        },
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
                              .withValues(alpha: 0.5)),
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
                              .withValues(alpha: 0.5)),
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
      ),
    );
  }

  AlertDialog _mainBatteryDiagnosticDialog(
      BuildContext context, ScooterBatteryType type, int soc, int? cycles) {
    return AlertDialog(
      title: Text(
        FlutterI18n.translate(
          context,
          "stats_diagnostics_title",
          translationParams: {"type": type.name(context).toUpperCase()},
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SOC: $soc%"),
          if (cycles != null)
            Text(
                "${FlutterI18n.translate(context, "stats_battery_cycles")}: $cycles"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_range")}: ${(45 * (soc / 100)).round()} km"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_capacity")}: ${(soc * 450).round()} Wh / 45000 Wh"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_last_update")}: ${context.select<ScooterService, DateTime?>(
                    (service) => service.lastPing,
                  )?.toString().split('.').first ?? "Never"}"),
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

  AlertDialog _nfcBatteryDiagnosticDialog(
      BuildContext context, int soc, int? cycles) {
    return AlertDialog(
      title: Text(
        FlutterI18n.translate(
          context,
          "stats_diagnostics_title",
          translationParams: {"type": "NFC"},
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SOC: $soc%"),
          if (cycles != null)
            Text(
                "${FlutterI18n.translate(context, "stats_battery_cycles")}: $cycles"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_range")}: ${(45 * (soc / 100)).round()} km"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_capacity")}: ${(soc * 450).round()} Wh / 45000 Wh"),
          Text(
              "${FlutterI18n.translate(context, "stats_battery_read_method")}: NFC"),
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
}
