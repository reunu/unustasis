import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  const Header(
    this.title, {
    this.subtitle,
    this.padding,
    this.level = 0,
    super.key,
  });

  final String title;
  final String? subtitle;
  final EdgeInsets? padding;

  /// 0 for a section heading, 1 for a subsection under one.
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    final isSubsection = level > 0;
    return Padding(
      padding: padding ??
          (isSubsection
              ? const EdgeInsets.fromLTRB(16, 20, 16, 4)
              : const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: isSubsection
                  ? Theme.of(context).textTheme.titleMedium!.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      )
                  : Theme.of(context).textTheme.headlineSmall!.copyWith(color: color)),
          if (subtitle != null) const SizedBox(height: 2),
          if (subtitle != null)
            Text(subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium!
                    .copyWith(color: color)),
        ],
      ),
    );
  }
}
