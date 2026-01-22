import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  const Header(
    this.title, {
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
    super.key,
  });

  final String title;
  final String? subtitle;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall!
                  .copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
          if (subtitle != null) const SizedBox(height: 2),
          if (subtitle != null)
            Text(subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium!
                    .copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}
