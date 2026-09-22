import 'package:flutter/material.dart';

/// Window width above which content is laid out for a wide display.
const double wideDisplayBreakpoint = 600;

/// Adds the wide-display horizontal inset on top of [base], and returns [base]
/// unchanged on phone-width windows.
EdgeInsets wideContentPadding(
  BuildContext context, {
  EdgeInsets base = EdgeInsets.zero,
  double inset = 80,
}) {
  if (MediaQuery.sizeOf(context).width <= wideDisplayBreakpoint) return base;
  return EdgeInsets.fromLTRB(
    base.left + inset,
    base.top,
    base.right + inset,
    base.bottom,
  );
}

/// Centres [child] and caps it at [maxWidth].
class WideContent extends StatelessWidget {
  const WideContent({super.key, required this.child, this.maxWidth = 600});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Max width for dialogs and bottom sheets.
const BoxConstraints wideDialogConstraints = BoxConstraints(maxWidth: 600);
