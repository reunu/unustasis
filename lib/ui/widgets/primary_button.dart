import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({required this.text, required this.onPressed, this.icon, this.busy = false, super.key});

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = Text(text, textAlign: TextAlign.center);
    final leading = busy
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colors.onSurface))
        : icon == null
            ? null
            : Icon(icon, size: 20);
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        backgroundColor: colors.onSurface,
        foregroundColor: colors.onTertiary,
      ),
      onPressed: busy ? null : onPressed,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: leading == null
            ? label
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [leading, const SizedBox(width: 8), Flexible(child: label)],
              ),
      ),
    );
  }
}
