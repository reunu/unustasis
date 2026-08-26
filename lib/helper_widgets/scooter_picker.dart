import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

import '../domain/scooter_candidate.dart';

/// The list of scooters found during onboarding, one row each, strongest
/// signal first. With a single scooter around this is a one-row list and
/// picking it is still a single tap.
class ScooterPicker extends StatelessWidget {
  const ScooterPicker({
    super.key,
    required this.candidates,
    required this.onSelected,
    this.maxHeight = 260,
  });

  final List<ScooterCandidate> candidates;
  final void Function(ScooterCandidate candidate) onSelected;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: candidates.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return _ScooterPickerTile(
            candidate: candidates[index],
            onTap: () => onSelected(candidates[index]),
          );
        },
      ),
    );
  }
}

class _ScooterPickerTile extends StatelessWidget {
  const _ScooterPickerTile({required this.candidate, required this.onTap});

  final ScooterCandidate candidate;
  final VoidCallback onTap;

  String _status(BuildContext context) {
    if (candidate.systemConnected) {
      return FlutterI18n.translate(context, "onboarding_picker_connected");
    }
    if (candidate.bonded) {
      return FlutterI18n.translate(context, "onboarding_picker_bonded");
    }
    return FlutterI18n.translate(context, "onboarding_picker_new");
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool known = candidate.bonded || candidate.systemConnected;
    final String name = candidate.name?.trim().isNotEmpty == true
        ? candidate.name!.trim()
        : FlutterI18n.translate(context, "onboarding_picker_unnamed");

    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _SignalIndicator(candidate: candidate),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      candidate.addressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          known ? Icons.link : Icons.bluetooth_searching,
                          size: 14,
                          color: known ? colors.primary : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _status(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: known ? colors.primary : colors.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four bars plus the raw dBm value. A scooter the phone is already connected
/// to never advertises, so there is no RSSI to show for it at all.
class _SignalIndicator extends StatelessWidget {
  const _SignalIndicator({required this.candidate});

  final ScooterCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int? bars = candidate.signalBars;
    final int? rssi = candidate.rssi;

    return SizedBox(
      width: 44,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bars == null)
            Icon(
              candidate.systemConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              size: 20,
              color: candidate.systemConnected ? colors.primary : colors.onSurfaceVariant,
            )
          else
            SizedBox(
              height: 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final bool lit = index < bars;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 4,
                      height: 6.0 + index * 4.5,
                      decoration: BoxDecoration(
                        color: lit ? colors.primary : colors.onSurfaceVariant.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            rssi != null
                ? FlutterI18n.translate(context, "onboarding_picker_rssi", translationParams: {"rssi": "$rssi"})
                : "",
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}
