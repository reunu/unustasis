import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/format_utils.dart';

class CloudScooterCard extends StatelessWidget {
  final Map<String, dynamic> scooter;
  final bool expanded;

  const CloudScooterCard({
    super.key,
    required this.scooter,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainer
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.surfaceContainer,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expanded)
            Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  FlutterI18n.translate(context, "cloud_scooter_linked"),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
          if (expanded) const SizedBox(height: 16),
          Row(
            children: [
              if (expanded)
                Image.asset(
                  "images/scooter/side_${scooter['color_id'] ?? 1}.webp",
                  height: 80,
                ),
              if (expanded) const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (expanded? scooter['name']: FlutterI18n.translate(context, "cloud_scooter_linked_to").replaceAll('{name}', scooter['name'])),
                      style: expanded
                          ? Theme.of(context).textTheme.headlineSmall
                          : Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      FlutterI18n.translate(context, "cloud_last_sync",
                          translationParams: {
                            "time": FormatUtils.formatLastSeen(
                                scooter['last_seen_at'],
                                short: !expanded)
                          }),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.exit_to_app_outlined),
                onPressed: () async {
                  final Uri url = Uri.parse(
                      'https://sunshine.rescoot.org/scooters/${scooter['id']}');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                tooltip: FlutterI18n.translate(context, "cloud_view_scooter"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
