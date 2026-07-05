import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/domain/ota_protocol.dart';
import 'package:unustasis/domain/update_planner.dart';

/// Builds a release-index entry the way downloads.librescoot.org serves it.
Map<String, dynamic> release(String tag,
    {bool prerelease = true, List<String> variants = const ["unu-mdb", "unu-dbc"], bool delta = true, bool mender = true}) {
  final assets = <Map<String, dynamic>>[];
  for (final v in variants) {
    if (mender) {
      assets.add({
        "name": "librescoot-$v-$tag.mender",
        "url": "https://dl/$tag/librescoot-$v-$tag.mender",
        "size": 500 * 1024 * 1024,
      });
    }
    if (delta) {
      assets.add({
        "name": "librescoot-$v-$tag.delta",
        "url": "https://dl/$tag/librescoot-$v-$tag.delta",
        "size": 30 * 1024 * 1024,
      });
    }
  }
  return {"tag_name": tag, "prerelease": prerelease, "assets": assets};
}

List<FirmwareRelease> parseIndex(List<Map<String, dynamic>> raw) {
  // Round-trip through JSON like the screen does.
  final decoded = jsonDecode(jsonEncode(raw)) as List<dynamic>;
  return [for (final r in decoded) FirmwareRelease.fromJson(r as Map<String, dynamic>)];
}

void main() {
  // Newest-first, like the real index. n1 < n2 < n3 chronologically.
  const n1 = "nightly-20260101T000000";
  const n2 = "nightly-20260102T000000";
  const n3 = "nightly-20260103T000000";
  final nightlyIndex = parseIndex([
    release(n3),
    release(n2),
    release(n1),
  ]);

  group("normalizeVersion", () {
    test("lowercases and keeps channel prefix", () {
      expect(UpdatePlanner.normalizeVersion("Nightly-20260101T000000", "nightly"),
          "nightly-20260101t000000");
    });
    test("prefixes bare nightly timestamps", () {
      expect(UpdatePlanner.normalizeVersion("20260101T000000", "nightly"),
          "nightly-20260101t000000");
    });
    test("prefixes stable without v", () {
      expect(UpdatePlanner.normalizeVersion("1.2.3", "stable"), "v1.2.3");
      expect(UpdatePlanner.normalizeVersion("v1.2.3", "stable"), "v1.2.3");
    });
  });

  group("inferChannel", () {
    test("recognizes channels", () {
      expect(UpdatePlanner.inferChannel("nightly-20260101T000000"), "nightly");
      expect(UpdatePlanner.inferChannel("testing-20260101T000000"), "testing");
      expect(UpdatePlanner.inferChannel("v1.2.3"), "stable");
      expect(UpdatePlanner.inferChannel("1.2.3"), "stable");
    });
    test("null for unknown or missing", () {
      expect(UpdatePlanner.inferChannel(null), null);
      expect(UpdatePlanner.inferChannel("unknown"), null);
      expect(UpdatePlanner.inferChannel("custom-build"), null);
    });
  });

  group("compareTags", () {
    test("stable is semver-aware", () {
      expect(UpdatePlanner.compareTags("v0.10.0", "v0.2.0", "stable"), 1);
      expect(UpdatePlanner.compareTags("v0.2.0", "v0.10.0", "stable"), -1);
      expect(UpdatePlanner.compareTags("v1.0.0", "v1.0.0", "stable"), 0);
    });
    test("nightly is lexicographic on timestamps", () {
      expect(UpdatePlanner.compareTags(n2, n1, "nightly"), 1);
      expect(UpdatePlanner.compareTags(n1, n2, "nightly"), -1);
    });
  });

  group("deltaCandidates / nextDelta", () {
    test("sorted ascending, next after current", () {
      final chain = UpdatePlanner.deltaCandidates(nightlyIndex, "nightly", "unu-mdb");
      expect([for (final r in chain) r.tagName], [n1, n2, n3]);

      final nd = UpdatePlanner.nextDelta(chain, n1, "nightly");
      expect(nd.currentFound, true);
      expect(nd.next?.tagName, n2);
    });

    test("up to date at latest", () {
      final chain = UpdatePlanner.deltaCandidates(nightlyIndex, "nightly", "unu-mdb");
      final nd = UpdatePlanner.nextDelta(chain, n3, "nightly");
      expect(nd.currentFound, true);
      expect(nd.next, null);
    });

    test("current not in chain", () {
      final chain = UpdatePlanner.deltaCandidates(nightlyIndex, "nightly", "unu-mdb");
      final nd = UpdatePlanner.nextDelta(chain, "nightly-20251231t000000", "nightly");
      expect(nd.currentFound, false);
      expect(nd.next, null);
    });

    test("wrong-variant and wrong-channel releases are excluded", () {
      final index = parseIndex([
        release(n2, variants: ["rpi5"]),
        release("testing-20260102T000000"),
        release("v1.0.0", prerelease: false),
        release(n1),
      ]);
      final chain = UpdatePlanner.deltaCandidates(index, "nightly", "unu-mdb");
      expect([for (final r in chain) r.tagName], [n1]);
    });
  });

  group("bundleId", () {
    final r = parseIndex([release(n2)]).first;

    test("mender drops the extension", () {
      final step = UpdateStep(
        component: OtaProtocol.componentMdb,
        release: r,
        asset: r.menderAsset("unu-mdb")!,
        kind: StepKind.full,
      );
      expect(step.bundleId, "librescoot-unu-mdb-$n2");
    });

    test("delta keeps the extension", () {
      final step = UpdateStep(
        component: OtaProtocol.componentMdb,
        release: r,
        asset: r.deltaAsset("unu-mdb")!,
        kind: StepKind.delta,
      );
      expect(step.bundleId, "librescoot-unu-mdb-$n2.delta");
    });

    test("rejects oversized or unsafe ids", () {
      final bad = UpdateStep(
        component: OtaProtocol.componentMdb,
        release: r,
        asset: FirmwareAsset(name: "../evil.delta", url: "https://dl/x", size: 1),
        kind: StepKind.delta,
      );
      expect(() => bad.bundleId, throwsStateError);

      final long = UpdateStep(
        component: OtaProtocol.componentMdb,
        release: r,
        asset: FirmwareAsset(name: "${"a" * 70}.delta", url: "https://dl/x", size: 1),
        kind: StepKind.delta,
      );
      expect(() => long.bundleId, throwsStateError);
    });
  });

  group("buildPlan", () {
    test("both boards one behind: MDB delta first, then DBC", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: n2,
        dbcVersion: n2,
      );
      expect(plan.upToDate, false);
      expect(plan.steps.length, 2);
      expect(plan.steps[0].component, OtaProtocol.componentMdb);
      expect(plan.steps[0].kind, StepKind.delta);
      expect(plan.steps[0].release.tagName, n3);
      expect(plan.steps[1].component, OtaProtocol.componentDbc);
      expect(plan.steps[1].kind, StepKind.delta);
    });

    test("up to date", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: n3,
        dbcVersion: n3,
      );
      expect(plan.upToDate, true);
      expect(plan.steps, isEmpty);
    });

    test("diverged boards: older DBC converges to MDB's version via delta", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: n2,
        dbcVersion: n1,
      );
      // Older DBC jumps the queue to converge on the MDB's version...
      expect(plan.steps.first.component, OtaProtocol.componentDbc);
      expect(plan.steps.first.kind, StepKind.convergeDelta);
      expect(plan.steps.first.release.tagName, n2);
      // ...then the preview continues to latest, MDB first.
      expect(plan.steps.length, 3);
      expect(plan.steps[1].component, OtaProtocol.componentMdb);
      expect(plan.steps[1].release.tagName, n3);
      expect(plan.steps[2].component, OtaProtocol.componentDbc);
      expect(plan.steps[2].release.tagName, n3);
    });

    test("diverged boards: older MDB converges via full when gap > one delta", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: n1,
        dbcVersion: n3,
      );
      expect(plan.steps.first.component, OtaProtocol.componentMdb);
      expect(plan.steps.first.kind, StepKind.convergeFull);
      expect(plan.steps.first.release.tagName, n3);
    });

    test("channel switch forces full images for both boards", () {
      final index = parseIndex([
        release("testing-20260105T000000"),
        release(n3),
      ]);
      final plan = UpdatePlanner.buildPlan(
        releases: index,
        channel: "testing",
        mdbVersion: n3,
        dbcVersion: n3,
        channelSwitch: true,
      );
      expect(plan.warnings, isNotEmpty);
      expect(plan.steps.length, 2);
      expect(plan.steps[0].component, OtaProtocol.componentMdb);
      expect(plan.steps[0].kind, StepKind.channelSwitchFull);
      expect(plan.steps[1].component, OtaProtocol.componentDbc);
      expect(plan.steps[1].kind, StepKind.channelSwitchFull);
    });

    test("off-channel MDB version is treated as a channel switch", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: "v1.0.0",
        dbcVersion: "v1.0.0",
      );
      expect(plan.steps.every((s) => s.kind == StepKind.channelSwitchFull), true);
    });

    test("unknown MDB version degrades to latest full MDB image", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: null,
        dbcVersion: null,
      );
      expect(plan.steps.length, 1);
      expect(plan.steps.first.component, OtaProtocol.componentMdb);
      expect(plan.steps.first.kind, StepKind.full);
      expect(plan.steps.first.release.tagName, n3);
      expect(plan.warnings, isNotEmpty);
    });

    test("unknown DBC version: MDB proceeds, warning asks to boot dashboard", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: n2,
        dbcVersion: "unknown",
      );
      expect(plan.steps.length, 1);
      expect(plan.steps.first.component, OtaProtocol.componentMdb);
      expect(plan.steps.first.kind, StepKind.delta);
      expect(plan.warnings.any((w) => w.contains("Dashboard version unknown")), true);
    });

    test("cross-channel DBC gets a full image at MDB's version", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: n2,
        dbcVersion: "testing-20260101T000000",
      );
      expect(plan.steps.first.component, OtaProtocol.componentDbc);
      expect(plan.steps.first.kind, StepKind.convergeFull);
      expect(plan.steps.first.release.tagName, n2);
    });

    test("no delta path: full image with warning", () {
      final plan = UpdatePlanner.buildPlan(
        releases: nightlyIndex,
        channel: "nightly",
        mdbVersion: "nightly-20251201T000000", // predates the chain
        dbcVersion: "nightly-20251201T000000",
      );
      expect(plan.steps.length, 2);
      expect(plan.steps.every((s) => s.kind == StepKind.full), true);
      expect(plan.steps.every((s) => s.release.tagName == n3), true);
      expect(plan.warnings.any((w) => w.contains("No delta path")), true);
    });

    test("newer full-only release without a delta yet", () {
      final index = parseIndex([
        release(n3, delta: false),
        release(n2),
        release(n1),
      ]);
      final plan = UpdatePlanner.buildPlan(
        releases: index,
        channel: "nightly",
        mdbVersion: n2,
        dbcVersion: n2,
      );
      expect(plan.steps.length, 2);
      expect(plan.steps.every((s) => s.kind == StepKind.full), true);
      expect(plan.steps.every((s) => s.release.tagName == n3), true);
    });

    test("stable channel uses semver ordering", () {
      final index = parseIndex([
        release("v0.10.0", prerelease: false),
        release("v0.9.0", prerelease: false),
        release("v0.2.0", prerelease: false),
      ]);
      final plan = UpdatePlanner.buildPlan(
        releases: index,
        channel: "stable",
        mdbVersion: "0.9.0",
        dbcVersion: "v0.9.0",
      );
      expect(plan.steps.length, 2);
      expect(plan.steps.every((s) => s.release.tagName == "v0.10.0"), true);
      expect(plan.steps.every((s) => s.kind == StepKind.delta), true);
    });
  });
}
