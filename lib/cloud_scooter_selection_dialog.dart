import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import '../domain/format_utils.dart';
import 'scooter_service.dart';

class ScooterSelectionDialog extends StatelessWidget {
  final List<Map<String, dynamic>> scooters;
  final Function(Map<String, dynamic>) onSelect;
  final int? currentlyAssignedId;
  final List<int> assignedIds;

  final log = Logger('ScooterSelectionDialog');

  ScooterSelectionDialog({
    super.key,
    required this.scooters,
    required this.onSelect,
    this.currentlyAssignedId,
    this.assignedIds = const [],
  });

  String _getAssignmentStatus(BuildContext context, Map<String, dynamic> scooter) {
    final deviceIds = scooter['device_ids'] as Map<String, dynamic>?;
    if (deviceIds == null || deviceIds.isEmpty) {
      return FlutterI18n.translate(context, "cloud_not_linked");
    }
    
    // Find any local scooter that matches the device IDs
    final scooterService = context.read<ScooterService>();
    final matchingScooters = scooterService.savedScooters.values.where((saved) {
      return deviceIds.containsValue(saved.id.toLowerCase());
    }).toList();

    if (matchingScooters.isEmpty) {
      return FlutterI18n.translate(context, "cloud_not_linked");
    }
    
    return FlutterI18n.translate(context, "cloud_scooter_linked_to",
      translationParams: {"name": matchingScooters.first.name}
    );
  }

  Future<bool> _confirmReassignment(BuildContext context, Map<String, dynamic> scooter) async {
    final currentAssignment = _getAssignmentStatus(context, scooter);
    
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(FlutterI18n.translate(context, "cloud_reassign_title")),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(FlutterI18n.translate(
              context, 
              "cloud_reassign_message",
              translationParams: {"name": scooter['name']}
            )),
            const SizedBox(height: 8),
            Text(
              currentAssignment,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(FlutterI18n.translate(context, "cloud_reassign_cancel")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(FlutterI18n.translate(context, "cloud_reassign_confirm")),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(FlutterI18n.translate(context, "cloud_select_scooter")),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: scooters.length,
          itemBuilder: (context, index) {
            final scooter = scooters[index];
            final bool isCurrentlyAssigned = scooter['id'] as int == currentlyAssignedId;
            final deviceIds = scooter['device_ids'] as Map<String, dynamic>?;
            final bool isAssignedToOther = deviceIds != null && deviceIds.isNotEmpty && !isCurrentlyAssigned;

            return ListTile(
              leading: Stack(
                children: [
                  Image.asset(
                    "images/scooter/side_${scooter['color_id'] ?? 1}.webp",
                    height: 80,
                    color: isAssignedToOther ? Colors.grey : null,
                    colorBlendMode:
                        isAssignedToOther ? BlendMode.saturation : null,
                  ),
                  if (isCurrentlyAssigned)
                    const Positioned(
                      left: 0,
                      top: 0,
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                    ),
                ],
              ),
              title: Text(
                scooter['name'],
                style: TextStyle(
                  color: isAssignedToOther
                      ? Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withValues(alpha: 0.5)
                      : null,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getAssignmentStatus(context, scooter),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isAssignedToOther
                              ? Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.5)
                              : null,
                        ),
                  ),
                  Text(
                    'Last seen: ${FormatUtils.formatLastSeen(scooter['last_seen_at'])}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isAssignedToOther
                              ? Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.color
                                  ?.withValues(alpha: 0.5)
                              : null,
                        ),
                  ),
                ],
              ),
              onTap: () async {
                if (isAssignedToOther) {
                  final shouldReassign =
                      await _confirmReassignment(context, scooter);
                  if (shouldReassign && context.mounted) {
                    onSelect(scooter);
                    Navigator.pop(context);
                  }
                } else {
                  onSelect(scooter);
                  Navigator.pop(context);
                }
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(FlutterI18n.translate(context, "cloud_select_cancel")),
        ),
      ],
    );
  }
}
