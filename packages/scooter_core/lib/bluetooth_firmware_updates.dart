/// Whether the MDB OS version supports firmware updates over Bluetooth.
///
/// Use the MDB version, never the dashboard or nRF version. Unknown/custom
/// versions fail closed. Stable releases require >=1.2.0; nightly/testing
/// builds require a valid date on or after 2026-08-03.
bool supportsBluetoothFirmwareUpdates(String? mdbVersion) {
  if (mdbVersion == null) return false;
  final version = mdbVersion.trim();
  final dated = RegExp(
          r'^(nightly|testing)-(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2}))?$')
      .firstMatch(version);
  if (dated != null) {
    final year = int.parse(dated[2]!);
    final month = int.parse(dated[3]!);
    final day = int.parse(dated[4]!);
    final hour = int.parse(dated[5] ?? '0');
    final minute = int.parse(dated[6] ?? '0');
    final second = int.parse(dated[7] ?? '0');
    final date = DateTime.utc(year, month, day, hour, minute, second);
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        date.hour != hour ||
        date.minute != minute ||
        date.second != second) {
      return false;
    }
    return !date.isBefore(DateTime.utc(2026, 8, 3));
  }

  final semver = RegExp(
    r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
  ).firstMatch(version);
  if (semver == null) return false;
  final prerelease = semver[4];
  if (prerelease != null) {
    for (final identifier in prerelease.split('.')) {
      if (RegExp(r'^\d+$').hasMatch(identifier) &&
          identifier.length > 1 &&
          identifier.startsWith('0')) return false;
    }
  }
  // BigInt avoids overflow for otherwise valid SemVer numeric components.
  final major = BigInt.parse(semver[1]!);
  final minor = BigInt.parse(semver[2]!);
  final patch = BigInt.parse(semver[3]!);
  if (major != BigInt.one) return major > BigInt.one;
  if (minor != BigInt.two) return minor > BigInt.two;
  return patch > BigInt.zero || (patch == BigInt.zero && prerelease == null);
}
