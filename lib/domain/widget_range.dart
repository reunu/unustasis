/// Matches the app's nominal estimate: 45 km per fully charged battery.
/// This is a last-known estimate, not a measured remaining distance. The gauge
/// uses the scooter's two-battery maximum of 90 km, not battery percentage.
int? estimatedWidgetRangeKm(int? primarySOC, int? secondarySOC) {
  int? valid(int? soc) => soc == null || soc < 0 ? null : soc.clamp(0, 100).toInt();
  final primary = valid(primarySOC);
  final secondary = valid(secondarySOC);
  if (primary == null && secondary == null) return null;
  return (((primary ?? 0) + (secondary ?? 0)) * 0.45).round();
}
