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

  Future<bool> _confirmReassignment(BuildContext context, Map<String, dynamic> scooter) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(FlutterI18n.translate(context, "cloud_reassign_title")),
        content: Text(FlutterI18n.translate(
          context, 
          "cloud_reassign_message",
          translationParams: {"name": scooter['name']}
        )),
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
            final bool isAssigned = assignedIds.contains(scooter['id'] as int);
            final bool isCurrentlyAssigned = scooter['id'] as int == currentlyAssignedId;
            
            return ListTile(
              enabled: !isAssigned || isCurrentlyAssigned,
              leading: Stack(
                children: [
                  Image.asset(
                    "images/scooter/side_${scooter['color_id'] ?? 1}.webp",
                    height: 40,
                    color: isAssigned && !isCurrentlyAssigned ? Colors.grey : null,
                    colorBlendMode: isAssigned && !isCurrentlyAssigned ? BlendMode.saturation : null,
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
                  color: isAssigned && !isCurrentlyAssigned 
                    ? Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 128)
                    : null,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VIN: ${scooter['vin'] ?? "Unknown"}',
                    style: TextStyle(
                      color: isAssigned && !isCurrentlyAssigned 
                        ? Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 128)
                        : null,
                    ),
                  ),
                  Text(
                    'Last seen: ${_formatLastSeen(scooter['last_seen_at'])}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isAssigned && !isCurrentlyAssigned 
                        ? Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 128)
                        : null,
                    ),
                  ),
                  if (scooter['location'] != null)
                    Text(
                      _formatLocation(context, scooter['location']),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isAssigned && !isCurrentlyAssigned 
                          ? Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 128)
                          : null,
                      ),
                    ),
                ],
              ),
              onTap: () async {
                if (isAssigned && !isCurrentlyAssigned) {
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