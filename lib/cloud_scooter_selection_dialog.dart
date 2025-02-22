import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';

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

  String _formatLastSeen(String lastSeenStr) {
    final lastSeen = DateTime.parse(lastSeenStr);
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return DateFormat('MMM d, HH:mm').format(lastSeen);
    }
  }

  String _formatLocation(BuildContext context, Map<String, dynamic> location) {
    if (location['lat'] == null || location['lng'] == null) {
      return FlutterI18n.translate(context, "cloud_no_location");
    }
    final lat = double.parse(location['lat'].toString());
    final lng = double.parse(location['lng'].toString());
    if (lat == 0.0 && lng == 0.0) {
      return FlutterI18n.translate(context, "cloud_no_location");
    }
    return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }

  String _getAssignmentStatus(BuildContext context, Map<String, dynamic> scooter) {
    final deviceIds = scooter['device_ids'] as Map<String, dynamic>?;
    if (deviceIds == null || deviceIds.isEmpty) {
      return FlutterI18n.translate(context, "cloud_not_assigned");
    }
    
    final List<String> assignments = [];
    if (deviceIds['android'] != null) {
      assignments.add('Android');
    }
    if (deviceIds['ios'] != null) {
      assignments.add('iOS');
    }
    
    return FlutterI18n.translate(context, "cloud_assigned_to",
      translationParams: {"platforms": assignments.join(", ")}
    );
  }

  Future<bool> _confirmReassignment(BuildContext context, Map<String, dynamic> scooter) async {
    final currentAssignments = _getAssignmentStatus(context, scooter);
    
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
              currentAssignments,
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
            final bool isAssignedToOtherDevice = 
              deviceIds != null && deviceIds.isNotEmpty && !isCurrentlyAssigned;
            
            return ListTile(
              leading: Stack(
                children: [
                  Image.asset(
                    "images/scooter/side_${scooter['color_id'] ?? 1}.webp",
                    height: 40,
                    color: isAssignedToOtherDevice ? Colors.grey : null,
                    colorBlendMode: isAssignedToOtherDevice ? BlendMode.saturation : null,
                  ),
                  if (isCurrentlyAssigned)
                    const Positioned(
                      right: 0,
                      bottom: 0,
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
                  color: isAssignedToOtherDevice 
                    ? Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.5)
                    : null,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VIN: ${scooter['vin'] ?? "Unknown"}',
                    style: TextStyle(
                      color: isAssignedToOtherDevice 
                        ? Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5)
                        : null,
                    ),
                  ),
                  Text(
                    _getAssignmentStatus(context, scooter),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isAssignedToOtherDevice 
                        ? Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5)
                        : null,
                    ),
                  ),
                  Text(
                    'Last seen: ${_formatLastSeen(scooter['last_seen_at'])}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isAssignedToOtherDevice 
                        ? Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5)
                        : null,
                    ),
                  ),
                  if (scooter['location'] != null)
                    Text(
                      _formatLocation(context, scooter['location']),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isAssignedToOtherDevice 
                          ? Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5)
                          : null,
                      ),
                    ),
                ],
              ),
              onTap: () async {
                if (isAssignedToOtherDevice) {
                  final shouldReassign = await _confirmReassignment(context, scooter);
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