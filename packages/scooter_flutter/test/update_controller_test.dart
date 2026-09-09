import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scooter_core/update_planner.dart';
import 'package:scooter_flutter/scooter_flutter.dart';
import 'navigation_runtime_test.dart' as nav;
import 'ota_transfer_service_test.dart' as ota;

class UpdateDevice extends nav.Device {
  UpdateDevice(super.id, super.trace);
  @override
  int get mtuNow => 247;
}

class UpdateRepository extends nav.Repository {
  UpdateRepository(UpdateDevice super.device, super.trace) {
    otaDataCharacteristic = data;
    otaControlCharacteristic = control;
    otaStatusCharacteristic = status;
    wire.onWrite = (v) async {
      if (v.startsWith('status:version:')) wire.reply('$v:$version');
    };
    control.onWrite = (v) async {
      if (v[0] == 5) status.values.add([0x84, probePhase, 42, 0]);
      if (v[0] == 1) status.values.add([0x81, 1, 0, 0, 0, 0, 2, 0, 1, 240, 0]);
      if (v[0] == 3) {
        status.values.add([0x83, 0]);
        if (installPhase != null) {
          status.values.add([0x84, installPhase!, 100, 0]);
        }
      }
    };
    data.onWrite = (v) async {
      final end = ota.OtaHarness.offset(v) + v.length - 4;
      status.values.add([0x82, 0, end & 255, end >> 8, 0, 0]);
    };
  }
  final data = ota.OtaCharacteristic(),
      control = ota.OtaCharacteristic(),
      status = ota.OtaCharacteristic();
  int probePhase = 6;
  int? installPhase = 4;
  String version = 'v1.0.0';
}

class UpdateEffects implements ScooterSessionEffects {
  late UpdateHarness h;
  @override
  void manualTargetChanged(String? id, {bool includeMetadata = false}) {}
  @override
  void invalidateTelemetry() => h.controller.invalidate();
  @override
  void linking(SessionConnection c) {}
  @override
  void transportConnected(SessionConnection c) {}
  @override
  Future<void> prepareIosWidget(SessionConnection c) async {}
  @override
  void wireTelemetry(SessionConnection c, CharacteristicRepository r) =>
      h.controller.bind(c, r);
  @override
  void readyMetadata(SessionConnection c) {}
  @override
  void ready(SessionConnection c) {
    if (h.autoReady) h.controller.sessionReady();
  }

  @override
  void disconnected(String? id) => h.controller.invalidate();
}

class ReleaseProvider implements UpdateReleaseProvider {
  List<FirmwareRelease> releases = [release('v2.0.0')];
  final channels = <String>[];
  final urls = <String>[];
  Completer<List<FirmwareRelease>>? indexGate;
  Completer<UpdateBundleDownload>? downloadGate;
  int closes = 0;
  List<int> bytes = [1, 2, 3];
  Object? indexError;
  @override
  Future<List<FirmwareRelease>> fetchIndex(String channel) async {
    channels.add(channel);
    if (indexError != null) throw indexError!;
    return indexGate == null ? releases : await indexGate!.future;
  }

  UpdateBundleDownload response() => UpdateBundleDownload(
      bytes: Stream.value(bytes), length: bytes.length, close: () => closes++);
  @override
  Future<UpdateBundleDownload> fetchBundle(FirmwareAsset asset) async {
    urls.add(asset.url);
    return downloadGate == null ? response() : await downloadGate!.future;
  }
}

FirmwareRelease release(String tag, {bool full = true, String hash = ''}) =>
    FirmwareRelease.fromJson({
      'tag_name': tag,
      'prerelease': !tag.startsWith('v'),
      'assets': [
        for (final ext in ['delta', if (full) 'mender'])
          {
            'name': 'librescoot-unu-mdb-$tag.$ext',
            'url': 'https://index-chosen-host/$tag.$ext',
            'size': 3,
            'sha256': hash,
          }
      ]
    });
UpdateStep stepFor(FirmwareRelease r, {bool full = false}) => UpdateStep(
    component: 0,
    release: r,
    asset: full ? r.menderAsset('unu-mdb')! : r.deltaAsset('unu-mdb')!,
    kind: full ? StepKind.full : StepKind.delta);

class UpdateHarness {
  UpdateHarness({void Function(String)? onTargetCaptured}) {
    final effects = UpdateEffects()..h = this;
    session = ScooterSession(
        flutterBluePlus: nav.Bluetooth(),
        effects: effects,
        onChanged: () {},
        findEligibleScooter: () async => null,
        isScanning: () => false,
        onStart: () {},
        isAndroid: false,
        isIOS: false,
        deviceFromId: (id) => devices[id]!,
        repositoryFactory: (d) => repos[d.remoteId.str]!);
    controller = UpdateController(
        session: session,
        provider: provider,
        onTargetCaptured: onTargetCaptured,
        channel: 'stable',
        cacheDirectory: () async {
          await cacheGate?.future;
          return dir;
        });
  }
  final provider = ReleaseProvider();
  late final ScooterSession session;
  late final UpdateController controller;
  final trace = <String>[];
  final devices = <String, UpdateDevice>{};
  final repos = <String, UpdateRepository>{};
  final allRepos = <UpdateRepository>[];
  final allDevices = <UpdateDevice>[];
  late Directory dir;
  Completer<void>? cacheGate;
  bool autoReady = false;
  UpdateRepository get repo => repos[session.device!.remoteId.str]!;
  Future<void> init() async {
    dir = await Directory.systemTemp.createTemp('update-controller');
    await connect('A');
  }

  Future<void> connect(String id) async {
    final device = UpdateDevice(id, trace);
    devices[id] = device;
    allDevices.add(device);
    repos[id] = UpdateRepository(device, trace);
    allRepos.add(repos[id]!);
    await session.connectToScooterId(id);
  }

  Future<void> close({bool disposeController = true}) async {
    if (disposeController) controller.dispose();
    session.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    for (final r in allRepos) {
      await r.wire.responses.close();
      await r.data.values.close();
      await r.control.values.close();
      await r.status.values.close();
    }
    for (final d in allDevices) {
      await d.states.close();
    }
    await dir.delete(recursive: true);
  }
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 200 && !predicate(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(predicate(), true,
      reason: 'controlled operation reached expected phase');
}

void main() {
  late UpdateHarness h;
  setUp(() async {
    h = UpdateHarness();
    await h.init();
  });
  tearDown(() async {
    await h.close();
  });
  test('query index plan prune download exact asset URL transfer', () async {
    final old = await File('${h.dir.path}/old.delta').writeAsString('old');
    await h.controller.refresh();
    expect(h.trace.where((s) => s.contains('status:version')),
        ['A:status:version:mdb', 'A:status:version:dbc']);
    expect(h.provider.channels, ['stable']);
    expect(h.controller.phase, UpdatePlanPhase.ready);
    expect(await old.exists(), false);
    final step = h.controller.plan!.steps.first;
    await h.controller.executeStep(step);
    expect(h.provider.urls, [step.asset.url]);
    expect(h.provider.closes, 1);
    expect(h.controller.transfer.state, OtaTransferState.success);
    expect(await File('${h.dir.path}/${step.asset.name}').readAsBytes(),
        [1, 2, 3]);
  });
  test('installed channel inference and deliberate switch use existing planner',
      () async {
    h.repo.version = 'nightly-20260101T000000';
    h.provider.releases = [release('nightly-20260102T000000')];
    await h.controller.refresh();
    expect(h.controller.channel, 'nightly');
    h.provider.releases = [release('v2.0.0')];
    await h.controller.refresh(channelSwitch: true, selectedChannel: 'stable');
    expect(h.controller.channelSwitch, true);
    expect(h.controller.plan!.steps.first.kind, StepKind.channelSwitchFull);
  });
  test('unknown versions and index failure preserve typed fallback/error',
      () async {
    h.repo.version = 'unknown';
    await h.controller.refresh();
    expect(h.controller.plan!.steps.length, 1);
    expect(h.controller.plan!.steps.first.isFullImage, true);
    h.provider.indexError = const UpdateHttpError(503, index: true);
    await h.controller.refresh();
    expect(h.controller.error, isA<UpdateCheckError>());
    expect(h.controller.phase, UpdatePlanPhase.error);
  });
  test('full fallback same release then newest supported channel full',
      () async {
    await h.controller.refresh();
    final same = stepFor(release('v1.5.0'));
    expect(h.controller.fullImageInstead(same)!.release.tagName, 'v1.5.0');
    final delta = stepFor(release('v1.5.0', full: false));
    expect(h.controller.fullImageInstead(delta)!.release.tagName, 'v2.0.0');
    h.provider.releases = [];
    await h.controller.refresh();
    expect(h.controller.fullImageInstead(delta), null);
  });
  test('valid same-size checksum cache reused; no provider call', () async {
    final step = stepFor(release('v2.0.0',
        hash: sha256.convert([1, 2, 3]).toString().toUpperCase()));
    await File('${h.dir.path}/${step.asset.name}').writeAsBytes([1, 2, 3]);
    await h.controller.executeStep(step);
    expect(h.provider.urls, isEmpty);
    expect(h.controller.transfer.state, OtaTransferState.success);
  });
  for (final cached in [true, false]) {
    test('checksum mismatch deletes ${cached ? "cached" : "downloaded"} bundle',
        () async {
      final step = stepFor(release('v2.0.0', hash: 'bad'));
      final file = File('${h.dir.path}/${step.asset.name}');
      if (cached) await file.writeAsBytes([1, 2, 3]);
      await h.controller.executeStep(step);
      expect(await file.exists(), false);
      expect(h.repo.data.writes, isEmpty);
      expect(h.controller.error.toString(), contains('checksum mismatch'));
      expect(h.provider.closes, cached ? 0 : 1);
    });
  }
  test(
      'partial size cache redownloaded; absent checksum preserves legacy acceptance',
      () async {
    final step = stepFor(release('v2.0.0'));
    await File('${h.dir.path}/${step.asset.name}').writeAsBytes([1]);
    await h.controller.executeStep(step);
    expect(h.provider.urls.length, 1);
    expect(h.controller.transfer.state, OtaTransferState.success);
  });
  for (final replacement in ['B', 'A', 'disconnect', 'dispose']) {
    Future<void> replace() async {
      if (replacement == 'disconnect') {
        h.devices['A']!.drop();
      } else if (replacement == 'dispose') {
        h.session.dispose();
        h.controller.invalidate();
      } else {
        if (replacement == 'A') h.devices['A']!.drop();
        await h.connect(replacement);
      }
    }

    test('stale index $replacement cannot publish a plan', () async {
      h.provider.indexGate = Completer();
      final run = h.controller.refresh();
      await until(() => h.provider.channels.isNotEmpty);
      await replace();
      h.provider.indexGate!.complete(h.provider.releases);
      await run;
      expect(h.controller.plan, null);
      expect(h.controller.phase, UpdatePlanPhase.idle);
    });
    test('stale download $replacement closes provider and never starts BLE',
        () async {
      final original = h.repo;
      h.provider.downloadGate = Completer();
      final run = h.controller.executeStep(stepFor(release('v2.0.0')));
      await until(() => h.provider.urls.isNotEmpty);
      await replace();
      h.provider.downloadGate!.complete(h.provider.response());
      await run;
      expect(original.control.writes, isEmpty);
      expect(h.provider.closes, 1);
      expect(h.controller.downloading, false);
      expect(h.controller.transfer.state, OtaTransferState.idle);
    });
    test('stale cached download $replacement never starts BLE', () async {
      final original = h.repo;
      final step = stepFor(release('v2.0.0'));
      await File('${h.dir.path}/${step.asset.name}').writeAsBytes([1, 2, 3]);
      h.cacheGate = Completer();
      final run = h.controller.executeStep(step);
      await Future<void>.delayed(Duration.zero);
      await replace();
      h.cacheGate!.complete();
      await run;
      expect(original.control.writes, isEmpty);
      expect(h.provider.urls, isEmpty);
    });
  }
  test('held MDB query replacement prevents DBC query and index fetch',
      () async {
    final gate = Completer<void>();
    final original = h.repo;
    original.wire.onWrite = (v) async {
      await gate.future;
      original.wire.reply('$v:v1.0.0');
    };
    final run = h.controller.refresh();
    await until(() => h.trace.contains('A:status:version:mdb'));
    await h.connect('B');
    gate.complete();
    await run;
    expect(h.trace.where((s) => s.contains('status:version')),
        ['A:status:version:mdb']);
    expect(h.provider.channels, isEmpty);
  });
  test(
      'download detach reattach retains progress and prevents duplicate work/prune',
      () async {
    var first = 0, second = 0;
    void listener1() => first++;
    void listener2() => second++;
    h.controller.addListener(listener1);
    h.provider.downloadGate = Completer();
    final step = stepFor(release('v2.0.0'));
    final run = h.controller.executeStep(step);
    await until(() => h.provider.urls.isNotEmpty);
    h.controller.removeListener(listener1);
    final detachedCount = first;
    await h.controller.executeStep(step);
    await h.controller.refresh(selectedChannel: 'nightly');
    h.controller.addListener(listener2);
    expect(h.controller.downloading, true);
    expect(h.controller.transfer.activeStep, same(step));
    h.provider.downloadGate!.complete(h.provider.response());
    await run;
    expect(first, detachedCount);
    expect(second, greaterThan(0));
    expect(h.provider.urls.length, 1);
    expect(h.provider.channels, isEmpty);
    expect(h.controller.channel, 'stable');
  });
  test(
      'accepted A disconnect B blocked then same-ID A confirmed without resend',
      () async {
    h.repo.installPhase = null;
    final original = h.repo;
    final run = h.controller.executeStep(stepFor(release('v2.0.0')));
    await until(
        () => h.controller.transfer.state == OtaTransferState.installing);
    h.devices['A']!.drop();
    await run;
    expect(h.controller.transfer.awaitingReconnect, true);
    expect(original.status.values.hasListener, false);
    await h.connect('B');
    await h.controller.refresh();
    await h.controller.executeStep(stepFor(release('v2.0.0')));
    expect(h.repo.control.writes, isEmpty);
    expect(h.trace.any((s) => s.startsWith('B:status')), false);
    expect(h.controller.targetId, 'A');
    await h.connect('A');
    h.repo.probePhase = 4;
    await h.controller.refresh();
    expect(h.repo.control.writes, [
      [5]
    ]);
    expect(h.repo.data.writes, isEmpty);
    expect(h.controller.transfer.state, OtaTransferState.success);
    expect(h.controller.transfer.awaitingReconnect, false);
  });
  test('stale STATUS response cannot adopt replacement install', () async {
    final original = h.repo;
    final gate = Completer<void>();
    original.control.onWrite = (_) async {
      await gate.future;
      original.status.values.add([0x84, 1, 80, 0]);
    };
    final run = h.controller.refresh();
    await until(() => original.control.writes.isNotEmpty);
    await h.connect('B');
    gate.complete();
    await run;
    expect(h.controller.transfer.state, OtaTransferState.idle);
    expect(original.status.values.hasListener, false);
    expect(h.provider.channels, isEmpty);
  });
  test('reentrant progress invalidation cannot start transfer', () async {
    h.controller.addListener(() {
      if (h.controller.downloadProgress == 1) h.devices['A']!.drop();
    });
    final original = h.repo;
    await h.controller.executeStep(stepFor(release('v2.0.0')));
    expect(original.control.writes, isEmpty);
    expect(h.provider.closes, 1);
  });
  test('pending reboot ready reconnect re-plans without a screen', () async {
    h.autoReady = true;
    h.repo.installPhase = 2;
    await h.controller.executeStep(stepFor(release('v2.0.0')));
    h.devices['A']!.drop();
    await h.connect('A');
    await until(() => h.controller.plan != null);
    expect(h.provider.channels, ['stable']);
    expect(h.controller.transfer.state, OtaTransferState.idle);
  });
}
