import 'package:flutter/material.dart';

class ScooterActionButton extends StatelessWidget {
  const ScooterActionButton({
    super.key,
    required void Function()? onPressed,
    required IconData icon,
    Color? iconColor,
    bool showBubble = false,
    required String label,
  })  : _onPressed = onPressed,
        _icon = icon,
        _iconColor = iconColor,
        _label = label,
        _showBubble = showBubble;

  final void Function()? _onPressed;
  final IconData _icon;
  final String _label;
  final Color? _iconColor;
  final bool _showBubble;

  @override
  Widget build(BuildContext context) {
    Color mainColor = _iconColor ??
        (_onPressed == null
            ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2)
            : Theme.of(context).colorScheme.onSurface);
    return Column(
      children: [
        Stack(
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(24),
                side: BorderSide(
                  color: mainColor,
                ),
              ),
              onPressed: _onPressed,
              child: Icon(
                _icon,
                color: mainColor,
              ),
            ),
            if (_showBubble)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: mainColor),
        ),
      ],
    );
  }
}
