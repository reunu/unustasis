import 'package:flutter/material.dart';
import 'dart:math';

class SnowfallBackground extends StatefulWidget {
  final Color backgroundColor;
  final Color snowflakeColor;

  const SnowfallBackground(
      {super.key, required this.backgroundColor, required this.snowflakeColor});

  @override
  SnowfallBackgroundState createState() => SnowfallBackgroundState();
}

class SnowfallBackgroundState extends State<SnowfallBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Snowflake>? _snowflakes; // Make _snowflakes nullable.
  final int _snowflakeCount = 100;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 20))
          ..repeat();

    _controller.addListener(() {
      setState(() {
        _snowflakes?.forEach((flake) => flake.updatePosition());
      });
    });
  }

  void _initializeSnowflakes(Size size) {
    _snowflakes = List.generate(
      _snowflakeCount,
      (_) => Snowflake(size.width, size.height),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Initialize snowflakes if they haven't been created yet.
    if (_snowflakes == null) {
      _initializeSnowflakes(MediaQuery.of(context).size);
    }

    return Container(
      color: widget.backgroundColor,
      child: CustomPaint(
        size: MediaQuery.of(context).size,
        painter: SnowPainter(_snowflakes ?? [], widget.snowflakeColor),
      ),
    );
  }
}

class Snowflake {
  late double x, y, speed, radius;

  Snowflake(double maxWidth, double maxHeight) {
    final random = Random();
    x = random.nextDouble() *
        maxWidth; // Now using the full width of the screen.
    y = random.nextDouble() *
        maxHeight; // Now using the full height of the screen.
    speed = 0.2 + random.nextDouble() * 0.8;
    radius = 0.5 + random.nextDouble() * 3;
  }

  void updatePosition() {
    y += speed;
  }
}

class SnowPainter extends CustomPainter {
  final List<Snowflake> snowflakes;
  final Color snowflakeColor;

  SnowPainter(this.snowflakes, this.snowflakeColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = snowflakeColor.withValues(alpha: 0.15);

    for (var flake in snowflakes) {
      // Ensure positions are constrained to the current canvas size.
      double flakeX = flake.x % size.width;
      double flakeY = flake.y % size.height;

      if (flakeY > size.height) {
        // Reset flake to the top when it goes beyond screen height.
        flakeY = 0;
        flake.x =
            Random().nextDouble() * size.width; // Randomize X position again.
      }

      canvas.drawCircle(Offset(flakeX, flakeY), flake.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
