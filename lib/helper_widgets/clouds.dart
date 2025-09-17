import 'dart:math';

import 'package:flutter/material.dart';

/// A lightweight widget that paints a slightly cloudy sky with
/// cartoon clouds slowly drifting by.
///
/// Usage: place `Clouds()` inside a Stack or column; it will expand to its
/// parent's width and height. You can customize [cloudCount] and [seed]
/// for reproducible randomness.
class Clouds extends StatefulWidget {
  /// Optional background color for the sky. If null, transparent.
  final Color? backgroundColor;

  // Single-purpose widget: fixed number of clouds.
  const Clouds({Key? key, this.backgroundColor}) : super(key: key);

  @override
  State<Clouds> createState() => _CloudsState();
}

class _CloudsState extends State<Clouds> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Cloud> _clouds;

  static const _assetPaths = [
    'images/decoration/cloud_0.webp',
    'images/decoration/cloud_1.webp',
    'images/decoration/cloud_2.webp',
  ];

  @override
  void initState() {
    super.initState();
    // deterministic placement; no RNG required

    // Single long-running controller. Individual clouds will use different
    // speed multipliers to achieve varied motion.
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 60))
      ..addListener(() => setState(() {}))
      ..repeat();

    const count = 7;
    _clouds = List.generate(count, (i) => _makeCloud(i, count));
  }

  _Cloud _makeCloud(int index, int total) {
    // deterministic image selection (cycle through available assets)
    final image = _assetPaths[index % _assetPaths.length];

    // One cloud per lane: lanes == total (we use 7 lanes)
    final lanes = max(1, total);

    // Evenly spread lanes across the full available height (with small margins)
    final topMargin = 0.04;
    final bottomMargin = 0.04;
    final laneFrac = lanes == 1 ? 0.5 : (index / (lanes - 1));
    final y = (topMargin + laneFrac * (1.0 - topMargin - bottomMargin)).clamp(0.0, 1.0);

    // Larger, consistent scale for bold clouds (reduced to avoid off-screen)
    final scale = 1.5; // uniform size

    // fixed marquee speed (all move to the right)
    final speed = 0.12;

    // Starting pattern: left / right / left / right ...
    // left starts off-screen at -baseWidth (offset 0.0), right starts near right edge (offset 0.92)
    // start closer to center: left-ish and right-ish positions
    final offset = (index % 2 == 0) ? 0.15 : 0.65;

    // subtle reduced opacity
    final opacity = 0.25;

    // no vertical bobbing for marquee motion
    final bob = 0.0;

    return _Cloud(
      image: image,
      y: y,
      scale: scale,
      speed: speed,
      offset: offset,
      opacity: opacity,
      bob: bob,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.of(context).size.width;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : MediaQuery.of(context).size.height * 0.3;

      return Container(
        width: w,
        height: h,
        color: widget.backgroundColor,
        child: Stack(children: [
          for (final cloud in _clouds) _buildCloud(cloud, w, h),
        ]),
      );
    });
  }

  Widget _buildCloud(_Cloud cloud, double width, double height) {
    // choose a base size relative to width (larger multiplier for a bolder look)
    // choose a base size relative to width (larger multiplier for a bolder look)
    final candidate = width * (0.32 * cloud.scale);
    // cap so a cloud never exceeds ~95% of the width
    final baseWidth = min(candidate, width * 0.95);
    final baseHeight = baseWidth * 0.75;

    // position progress 0..1 for controller
    final t = _ctrl.value;

    // compute x as fraction of width (wraps around)
    final frac = (cloud.offset + t * cloud.speed) % 1.0;

    // map frac so clouds move left->right and fully disappear off-screen
    final x = frac * (width + baseWidth) - baseWidth;

    // subtle vertical bobbing
    final bob = sin((t * 2 * pi + cloud.offset * 10)) * (cloud.bob / 2);

    final top = (cloud.y * height) + bob;

    return Positioned(
      left: x,
      top: top.clamp(0.0, max(0.0, height - baseHeight)),
      child: Opacity(
        opacity: cloud.opacity,
        child: Image.asset(
          cloud.image,
          width: baseWidth,
          height: baseHeight,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _Cloud {
  final String image;
  final double y;
  final double scale;
  final double speed;
  final double offset;
  final double opacity;
  final double bob;

  _Cloud({
    required this.image,
    required this.y,
    required this.scale,
    required this.speed,
    required this.offset,
    required this.opacity,
    required this.bob,
  });
}
