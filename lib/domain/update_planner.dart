import 'ota_protocol.dart';

/// Release selection for over-BLE firmware updates.
///
/// Mirrors update-service's algorithm (internal/updater/updater.go,
/// buildDeltaChain / findLatestRelease): instead of always offering the
/// newest full image, prefer the next `.delta` on top of the currently
/// installed version — deltas are a fraction of a full image, which matters
/// at BLE transfer speeds. Falls back to the full `.mender` when no delta
/// path exists, and forces full images across channel switches (deltas never
/// cross channels).

/// One downloadable file from the release index.
class FirmwareAsset {
  final String name;
  final String url;
  final int size;

  const FirmwareAsset({required this.name, required this.url, required this.size});

  bool get isDelta => name.endsWith(".delta");
  bool get isMender => name.endsWith(".mender");

  static FirmwareAsset? fromJson(Map<String, dynamic> json) {
    final name = json["name"] as String? ?? "";
    final url = json["url"] as String? ?? "";
    if (name.isEmpty || url.isEmpty) return null;
    return FirmwareAsset(name: name, url: url, size: (json["size"] as num?)?.toInt() ?? 0);
  }
}

/// One release from `https://downloads.librescoot.org/releases/<channel>.json`
/// (GitHub-releases-shaped, same index update-service consumes).
class FirmwareRelease {
  final String tagName;
  final bool prerelease;
  final List<FirmwareAsset> assets;

  const FirmwareRelease({required this.tagName, required this.prerelease, required this.assets});

  static FirmwareRelease fromJson(Map<String, dynamic> json) {
    final assets = <FirmwareAsset>[];
    for (final a in (json["assets"] as List<dynamic>? ?? [])) {
      final asset = FirmwareAsset.fromJson(a as Map<String, dynamic>);
      if (asset != null) assets.add(asset);
    }
    return FirmwareRelease(
      tagName: json["tag_name"] as String? ?? "",
      prerelease: json["prerelease"] as bool? ?? false,
      assets: assets,
    );
  }

  FirmwareAsset? deltaAsset(String variant) => _asset(variant, delta: true);
  FirmwareAsset? menderAsset(String variant) => _asset(variant, delta: false);

  FirmwareAsset? _asset(String variant, {required bool delta}) {
    for (final a in assets) {
      if (a.name.contains(variant) && (delta ? a.isDelta : a.isMender)) return a;
    }
    return null;
  }
}

enum StepKind {
  /// Next delta on top of the installed version.
  delta,

  /// Full image because no delta path exists from the installed version.
  full,

  /// Bring the older board to the newer board's version (delta path).
  convergeDelta,

  /// Bring the older board to the newer board's version (full image).
  convergeFull,

  /// Full image because the user switched channels.
  channelSwitchFull,
}

/// One transfer-and-install action. Only the first step of a plan is
/// actionable; the rest is a preview since each install changes the
/// installed version the next step must be computed from.
class UpdateStep {
  final int component; // OtaProtocol.componentMdb / componentDbc
  final FirmwareRelease release;
  final FirmwareAsset asset;
  final StepKind kind;

  const UpdateStep({
    required this.component,
    required this.release,
    required this.asset,
    required this.kind,
  });

  bool get isFullImage => kind != StepKind.delta && kind != StepKind.convergeDelta;

  /// The bundle_id sent in the OTA START message. Contract with
  /// bluetooth-service's staging (pkg/ota/staging.go stagedName): full images
  /// send the basename without ".mender" (the scooter appends it), deltas
  /// send the full filename so the ".delta" extension survives staging and
  /// update-service dispatches on it. Charset mirrors protocol.go
  /// validBundleID.
  String get bundleId {
    final id =
        asset.isMender ? asset.name.substring(0, asset.name.length - ".mender".length) : asset.name;
    if (id.length > 64 || !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(id)) {
      throw StateError("Asset name not usable as bundle id: ${asset.name}");
    }
    return id;
  }
}

/// A user-facing warning attached to a plan. Carries an i18n key (plus its
/// placeholder values) instead of text so the UI layer owns the wording.
class PlanWarning {
  final String key;
  final Map<String, String> params;

  const PlanWarning(this.key, [this.params = const {}]);
}

class UpdatePlan {
  final List<UpdateStep> steps;
  final List<PlanWarning> warnings;
  final bool upToDate;

  const UpdatePlan({required this.steps, required this.warnings, required this.upToDate});
}

/// Result of looking up the next delta for a version in the candidate chain.
class NextDelta {
  /// Whether the current version appears in the delta chain at all. When
  /// false, no delta path exists and a full image is required.
  final bool currentFound;
  final FirmwareRelease? next;

  const NextDelta({required this.currentFound, this.next});
}

class UpdatePlanner {
  static const String variantMdb = "unu-mdb";
  static const String variantDbc = "unu-dbc";
  static const List<String> channels = ["stable", "testing", "nightly"];

  static String variantFor(int component) =>
      component == OtaProtocol.componentDbc ? variantDbc : variantMdb;

  static bool isKnownVersion(String? version) =>
      version != null && version.trim().isNotEmpty && version.trim() != "unknown";

  /// The channel a version string implies: "nightly-..." / "testing-..." /
  /// v-or-digit-prefixed semver -> stable (mirrors update-service
  /// version.Channel). Null when undeterminable.
  static String? inferChannel(String? version) {
    if (!isKnownVersion(version)) return null;
    final v = version!.trim().toLowerCase();
    if (v.startsWith("nightly-")) return "nightly";
    if (v.startsWith("testing-")) return "testing";
    if (v.startsWith("v") || _startsWithDigit(v)) return "stable";
    return null;
  }

  static bool _startsWithDigit(String s) =>
      s.isNotEmpty && s.codeUnitAt(0) >= 0x30 && s.codeUnitAt(0) <= 0x39;

  /// Normalizes an installed version for comparison against release tags:
  /// lowercase, "v" prefix for stable, `<channel>-` prefix for bare
  /// nightly/testing timestamps (mirrors buildDeltaChain's normalization).
  static String normalizeVersion(String raw, String channel) {
    var v = raw.trim().toLowerCase();
    if (channel == "stable") {
      if (!v.startsWith("v")) v = "v$v";
    } else if (!v.startsWith("$channel-")) {
      v = "$channel-$v";
    }
    return v;
  }

  /// Compares release tags / normalized versions. Stable needs numeric
  /// semver comparison (v0.10.0 > v0.2.0); nightly/testing tags embed an ISO
  /// timestamp, so lowercase lexicographic is correct.
  static int compareTags(String a, String b, String channel) {
    final la = a.toLowerCase(), lb = b.toLowerCase();
    if (channel == "stable") {
      final pa = _parseSemver(la), pb = _parseSemver(lb);
      if (pa != null && pb != null) {
        for (var i = 0; i < 3; i++) {
          if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
        }
        return 0;
      }
    }
    return la.compareTo(lb).sign;
  }

  static List<int>? _parseSemver(String v) {
    if (!v.startsWith("v")) return null;
    final parts = v.substring(1).split("-").first.split(".");
    if (parts.length != 3) return null;
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      out.add(n);
    }
    return out;
  }

  /// Whether a release belongs to a channel (mirrors findLatestRelease):
  /// nightly/testing are prereleases with the channel tag prefix, stable are
  /// non-prereleases tagged "v...".
  static bool channelMatches(FirmwareRelease release, String channel) {
    switch (channel) {
      case "nightly":
        return release.prerelease && release.tagName.startsWith("nightly-");
      case "testing":
        return release.prerelease && release.tagName.startsWith("testing-");
      case "stable":
        return !release.prerelease && release.tagName.startsWith("v");
      default:
        return release.tagName.startsWith("$channel-");
    }
  }

  /// Channel-and-variant-filtered releases carrying a delta asset, sorted
  /// ascending — the delta chain (mirrors buildDeltaChain). A delta's
  /// filename names its target; its implicit source is the chain predecessor.
  static List<FirmwareRelease> deltaCandidates(
      List<FirmwareRelease> releases, String channel, String variant) {
    final candidates = [
      for (final r in releases)
        if (channelMatches(r, channel) && r.deltaAsset(variant) != null) r
    ];
    candidates.sort((a, b) => compareTags(a.tagName, b.tagName, channel));
    return candidates;
  }

  /// Finds the next delta after [normalizedCurrent] in the chain. The current
  /// version must itself appear in the chain, otherwise the implicit
  /// source-version contract is broken and a full image is required.
  static NextDelta nextDelta(
      List<FirmwareRelease> candidates, String normalizedCurrent, String channel) {
    final current = normalizedCurrent.toLowerCase();
    var currentFound = false;
    for (final r in candidates) {
      final tag = r.tagName.toLowerCase();
      if (tag == current) {
        currentFound = true;
        continue;
      }
      if (currentFound && compareTags(tag, current, channel) > 0) {
        return NextDelta(currentFound: true, next: r);
      }
    }
    return NextDelta(currentFound: currentFound);
  }

  /// The newest channel release carrying a full image for [variant].
  static FirmwareRelease? latestFull(
      List<FirmwareRelease> releases, String channel, String variant) {
    FirmwareRelease? best;
    for (final r in releases) {
      if (!channelMatches(r, channel) || r.menderAsset(variant) == null) continue;
      if (best == null || compareTags(r.tagName, best.tagName, channel) > 0) best = r;
    }
    return best;
  }

  static FirmwareRelease? _releaseByTag(
      List<FirmwareRelease> releases, String channel, String normalizedTag) {
    for (final r in releases) {
      if (channelMatches(r, channel) && r.tagName.toLowerCase() == normalizedTag) return r;
    }
    return null;
  }

  /// Builds the update plan. [mdbVersion] / [dbcVersion] are the raw versions
  /// reported by the scooter (null when the query failed, "unknown" when the
  /// scooter has no record). [channelSwitch] is set when the user picked a
  /// channel different from the installed one — deltas can't cross channels,
  /// so both boards get full images.
  static UpdatePlan buildPlan({
    required List<FirmwareRelease> releases,
    required String channel,
    required String? mdbVersion,
    required String? dbcVersion,
    bool channelSwitch = false,
  }) {
    final steps = <UpdateStep>[];
    final warnings = <PlanWarning>[];

    // A known MDB version on a different channel is a channel switch even if
    // the caller didn't flag it (e.g. restored app state).
    final mdbChannel = inferChannel(mdbVersion);
    final effectiveSwitch =
        channelSwitch || (mdbChannel != null && mdbChannel != channel);

    if (effectiveSwitch) {
      warnings.add(const PlanWarning("ls_ota_warn_channel_switch"));
      for (final component in [OtaProtocol.componentMdb, OtaProtocol.componentDbc]) {
        final release = latestFull(releases, channel, variantFor(component));
        if (release == null) continue;
        steps.add(UpdateStep(
          component: component,
          release: release,
          asset: release.menderAsset(variantFor(component))!,
          kind: StepKind.channelSwitchFull,
        ));
      }
      if (steps.isEmpty) {
        warnings.add(PlanWarning("ls_ota_warn_no_images", {"channel": channel}));
      }
      return UpdatePlan(steps: steps, warnings: warnings, upToDate: false);
    }

    if (!isKnownVersion(mdbVersion)) {
      // Degrades to the old behavior: newest full MDB image.
      warnings.add(const PlanWarning("ls_ota_warn_mdb_unknown"));
      final release = latestFull(releases, channel, variantMdb);
      if (release == null) {
        warnings.add(PlanWarning("ls_ota_warn_no_mdb_bundle", {"channel": channel}));
        return UpdatePlan(steps: const [], warnings: warnings, upToDate: false);
      }
      steps.add(UpdateStep(
        component: OtaProtocol.componentMdb,
        release: release,
        asset: release.menderAsset(variantMdb)!,
        kind: StepKind.full,
      ));
      return UpdatePlan(steps: steps, warnings: warnings, upToDate: false);
    }

    final normMdb = normalizeVersion(mdbVersion!, channel);
    final dbcKnown = isKnownVersion(dbcVersion);
    final dbcChannel = inferChannel(dbcVersion);

    if (!dbcKnown) {
      warnings.add(const PlanWarning("ls_ota_warn_dbc_unknown"));
      _addBoardSteps(steps, warnings, releases, channel, OtaProtocol.componentMdb, normMdb);
      return UpdatePlan(
          steps: steps, warnings: warnings, upToDate: steps.isEmpty && warnings.length == 1);
    }

    // Board divergence: bring the older board to the newer board's version
    // before anything else, so both advance in lockstep from there.
    if (dbcChannel != null && dbcChannel != channel) {
      // Cross-channel divergence: the scooter is the reference; the dashboard
      // needs a full image, deltas can't cross channels.
      warnings.add(PlanWarning("ls_ota_warn_dbc_channel", {"channel": dbcChannel}));
      final target = _releaseByTag(releases, channel, normMdb);
      final release = (target != null && target.menderAsset(variantDbc) != null)
          ? target
          : latestFull(releases, channel, variantDbc);
      if (release != null) {
        steps.add(UpdateStep(
          component: OtaProtocol.componentDbc,
          release: release,
          asset: release.menderAsset(variantDbc)!,
          kind: StepKind.convergeFull,
        ));
      } else {
        warnings.add(PlanWarning("ls_ota_warn_no_dbc_image", {"channel": channel}));
      }
      _addBoardSteps(steps, warnings, releases, channel, OtaProtocol.componentMdb, normMdb);
      return UpdatePlan(steps: steps, warnings: warnings, upToDate: false);
    }

    final normDbc = normalizeVersion(dbcVersion!, channel);
    var converged = normMdb;

    if (normMdb != normDbc) {
      final dbcOlder = compareTags(normDbc, normMdb, channel) < 0;
      final olderComponent = dbcOlder ? OtaProtocol.componentDbc : OtaProtocol.componentMdb;
      final olderNorm = dbcOlder ? normDbc : normMdb;
      final newerNorm = dbcOlder ? normMdb : normDbc;
      final variant = variantFor(olderComponent);

      final target = _releaseByTag(releases, channel, newerNorm);
      if (target == null) {
        // The newer board's version is no longer in the index; converge on
        // the latest instead.
        warnings.add(PlanWarning("ls_ota_warn_version_unpublished", {"version": newerNorm}));
        final release = latestFull(releases, channel, variant);
        if (release != null) {
          steps.add(UpdateStep(
            component: olderComponent,
            release: release,
            asset: release.menderAsset(variant)!,
            kind: StepKind.convergeFull,
          ));
        }
        converged = newerNorm;
      } else {
        final chain = deltaCandidates(releases, channel, variant);
        final nd = nextDelta(chain, olderNorm, channel);
        if (nd.next != null &&
            nd.next!.tagName.toLowerCase() == newerNorm &&
            target.deltaAsset(variant) != null) {
          steps.add(UpdateStep(
            component: olderComponent,
            release: target,
            asset: target.deltaAsset(variant)!,
            kind: StepKind.convergeDelta,
          ));
        } else if (target.menderAsset(variant) != null) {
          steps.add(UpdateStep(
            component: olderComponent,
            release: target,
            asset: target.menderAsset(variant)!,
            kind: StepKind.convergeFull,
          ));
        } else {
          warnings.add(PlanWarning("ls_ota_warn_no_image_for",
              {"board": dbcOlder ? "DBC" : "MDB", "version": newerNorm}));
        }
        converged = newerNorm;
      }
    }

    // From the (assumed) converged version, the next delta per board. The
    // scooter (MDB) is offered first; the dashboard only jumps the queue when
    // it must converge to a newer scooter version (divergence handling
    // above). Updates run one at a time, so after the MDB step completes and
    // the scooter reboots, the app reconnects, re-plans and then offers the
    // dashboard step.
    _addBoardSteps(steps, warnings, releases, channel, OtaProtocol.componentMdb, converged);
    _addBoardSteps(steps, warnings, releases, channel, OtaProtocol.componentDbc, converged);

    return UpdatePlan(
      steps: steps,
      warnings: warnings,
      upToDate: steps.isEmpty && warnings.isEmpty,
    );
  }

  /// Appends the next update step for one board starting from
  /// [normalizedCurrent]: the next delta in the chain, or the latest full
  /// image when the version has no delta path. No step when up to date.
  static void _addBoardSteps(
    List<UpdateStep> steps,
    List<PlanWarning> warnings,
    List<FirmwareRelease> releases,
    String channel,
    int component,
    String normalizedCurrent,
  ) {
    final variant = variantFor(component);
    final chain = deltaCandidates(releases, channel, variant);
    final nd = nextDelta(chain, normalizedCurrent, channel);

    if (nd.next != null) {
      steps.add(UpdateStep(
        component: component,
        release: nd.next!,
        asset: nd.next!.deltaAsset(variant)!,
        kind: StepKind.delta,
      ));
      return;
    }

    final latest = latestFull(releases, channel, variant);
    if (latest == null) return; // nothing published for this board
    if (compareTags(latest.tagName, normalizedCurrent, channel) <= 0) {
      return; // up to date
    }
    if (nd.currentFound) {
      // In the chain with nothing after it, but a newer full-only release
      // exists (no delta published for it yet).
      steps.add(UpdateStep(
        component: component,
        release: latest,
        asset: latest.menderAsset(variant)!,
        kind: StepKind.full,
      ));
      return;
    }
    warnings.add(PlanWarning("ls_ota_warn_no_delta_path",
        {"version": normalizedCurrent, "latest": latest.tagName}));
    steps.add(UpdateStep(
      component: component,
      release: latest,
      asset: latest.menderAsset(variant)!,
      kind: StepKind.full,
    ));
  }
}
