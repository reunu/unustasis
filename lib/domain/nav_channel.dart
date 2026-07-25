/// Where a navigation destination should be sent.
enum NavChannel {
  /// Straight over BLE to a connected scooter.
  ble,

  /// Through sunshine to a cloud-linked scooter that is online.
  cloud,

  /// Neither channel is up. Queue it and dispatch when one returns.
  pending,
}

/// Picks the channel for a navigation destination.
///
/// BLE first: it is the lower-latency path and the only one that can address a
/// scooter-side favourite by id. Cloud second. Queueing is the last resort, not
/// the normal path for a scooter that is merely out of Bluetooth range.
NavChannel navChannelFor({
  required bool bleReady,
  required bool cloudLinked,
  required bool cloudOnline,
}) {
  if (bleReady) return NavChannel.ble;
  if (cloudLinked && cloudOnline) return NavChannel.cloud;
  return NavChannel.pending;
}
