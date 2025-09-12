import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A simple animated background that renders falling autumn leaves.
///
/// Leaves are drawn procedurally (no image assets) and have randomized
/// size, speed, rotation and horizontal sway.
class LeavesBackground extends StatefulWidget {
  final Color backgroundColor;
  final List<Color> leafColors;
  final int leafCount;
  final bool showBottomDecoration;
  final bool showCornerDecorations;

  const LeavesBackground({
    super.key,
    required this.backgroundColor,
    this.leafColors = const [
      Color(0xFF8B4000), // brown
      Color(0xFFFF8C00), // dark orange
      Color(0xFFFFC107), // amber
      Color(0xFFB7410E), // russet
    ],
    this.leafCount = 20,
    this.showBottomDecoration = true,
    this.showCornerDecorations = true,
  });

  @override
  LeavesBackgroundState createState() => LeavesBackgroundState();
}

class LeavesBackgroundState extends State<LeavesBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<Leaf>? _leaves;
  List<ui.Image>? _leafImages;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Drive repaint on each tick.
    _controller.addListener(() {
      setState(() {
        _leaves?.forEach((l) => l.updatePosition());
      });
    });
  }

  void _initializeLeaves(Size size) {
    if (_leafImages == null || _leafImages!.isEmpty) {
      _leaves = [];
      return;
    }

    _leaves = List.generate(widget.leafCount, (i) {
      final img = _leafImages![i % _leafImages!.length];
      return Leaf.random(size.width, size.height, img);
    });
  }

  Future<List<ui.Image>> _loadLeafImages() async {
    final List<ui.Image> images = [];
    for (var i = 0; i < 6; i++) {
      try {
        final bytes = await rootBundle.load('images/decoration/leaf_$i.webp');
        final img = await decodeImageFromList(bytes.buffer.asUint8List());
        images.add(img);
      } catch (_) {
        // If any asset missing or fails to decode, skip it.
      }
    }
    return images;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Start loading images once.
    if (_leafImages == null) {
      _leafImages = [];
      _loadLeafImages().then((imgs) {
        if (mounted) {
          setState(() {
            _leafImages = imgs;
            // initialize leaves now that we have image sizes
            if ((_leaves == null) || _leaves!.isEmpty) {
              _initializeLeaves(size);
            }
          });
        }
      });
    }

    _leaves ??= [];

    return Container(
      color: widget.backgroundColor,
      child: Stack(
        children: [
          // Falling leaves painter
          Positioned.fill(
            child: CustomPaint(
              size: size,
              painter: _LeavesPainter(_leaves ?? [], repaint: _controller),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 56,
                width: double.infinity,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('images/decoration/leaves_b.webp'),
                    repeat: ImageRepeat.repeatX,
                    alignment: Alignment.topCenter,
                    fit: BoxFit.none,
                    filterQuality: FilterQuality.medium,
                    scale: 1.4,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SizedBox(
                height: 120,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Image.asset(
                      'images/decoration/leaves_l.webp',
                      fit: BoxFit.none,
                      scale: 1.5,
                      alignment: Alignment.topLeft,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SizedBox(
                height: 120,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Image.asset(
                      'images/decoration/leaves_r.webp',
                      fit: BoxFit.none,
                      scale: 1.5,
                      alignment: Alignment.topRight,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Leaf {
  double x;
  double y;
  double size;
  double speed;
  double rotation;
  double rotationSpeed;
  double swayAmplitude;
  double swayPhase;
  ui.Image image;
  double maxWidth;
  double maxHeight;

  Leaf({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.rotation,
    required this.rotationSpeed,
    required this.swayAmplitude,
    required this.swayPhase,
    required this.image,
    required this.maxWidth,
    required this.maxHeight,
  });

  factory Leaf.random(double maxWidth, double maxHeight, ui.Image image) {
    final rnd = Random();
    final size = 20 + rnd.nextDouble() * 40; // leaf size in px (20..60)
    return Leaf(
      x: rnd.nextDouble() * maxWidth,
      y: rnd.nextDouble() * maxHeight,
      size: size,
      // Slower vertical motion and gentler rotation for a calmer effect.
      speed: 1 + rnd.nextDouble() * 0.5,
      rotation: rnd.nextDouble() * pi * 2,
      rotationSpeed: (rnd.nextDouble() - 0.5) * 0.025,
      swayAmplitude: 8 + rnd.nextDouble() * 6,
      swayPhase: rnd.nextDouble() * pi * 2,
      image: image,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  void updatePosition() {
    y += speed;
    rotation += rotationSpeed;
    // Smaller sway increment and smaller horizontal displacement for slower motion.
    swayPhase += 0.006 + (rotationSpeed.abs() * 0.002);
    x += sin(swayPhase) * (swayAmplitude * 0.1);

    // Keep x within bounds, wrap horizontally.
    if (x < -size) x = maxWidth + size;
    if (x > maxWidth + size) x = -size;

    // When leaf falls below screen reset it to the top with new random params.
    if (y - size > maxHeight) {
      final rnd = Random();
      // Reset position (start slightly above) and re-randomize all motion
      // parameters using the same distributions as the initial generator.
      y = -rnd.nextDouble() * maxHeight * 0.2; // start slightly above
      x = rnd.nextDouble() * maxWidth;
      speed = 1 + rnd.nextDouble() * 0.5;
      rotation = rnd.nextDouble() * pi * 2;
      rotationSpeed = (rnd.nextDouble() - 0.5) * 0.025;
      swayAmplitude = 8 + rnd.nextDouble() * 6;
      swayPhase = rnd.nextDouble() * pi * 2;
      size = 20 + rnd.nextDouble() * 40;
    }
  }
}

class _LeavesPainter extends CustomPainter {
  final List<Leaf> leaves;
  final Animation<double>? repaint;

  _LeavesPainter(this.leaves, {this.repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // paint variable not needed for image drawing

    for (final leaf in leaves) {
      // If the canvas size changed since creation, update leaf bounds.
      leaf.maxWidth = size.width;
      leaf.maxHeight = size.height;

      final alpha = (0.7 + (sin(leaf.swayPhase) * 0.3)).clamp(0.2, 1.0).toDouble();

      // Ensure the leaf x coordinate is within a sane range to avoid disappearing
      // when size.width is zero or x goes out of bounds.
      double cx = leaf.x;
      if (size.width > 0) {
        if (cx < -leaf.size) cx = -leaf.size;
        if (cx > size.width + leaf.size) cx = size.width + leaf.size;
      } else {
        cx = 0.0;
      }
      final cy = leaf.y;

      // Draw the image centered at (cx, cy) with rotation and opacity.
      final img = leaf.image;
      final dstSize = Size(leaf.size, leaf.size * (img.height / img.width));
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(leaf.rotation);
      final dstRect = Rect.fromCenter(center: Offset.zero, width: dstSize.width, height: dstSize.height);
      final paintImage = Paint()
        ..colorFilter = ui.ColorFilter.mode(Colors.white.withOpacity(alpha), BlendMode.modulate);
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dstRect, paintImage);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
