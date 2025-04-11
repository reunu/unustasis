import 'package:flutter/material.dart';

import '../domain/theme_helper.dart';

class GrassScape extends StatelessWidget {
  const GrassScape({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          constraints: BoxConstraints.expand(),
          alignment: Alignment.center,
          child: Image.asset(
              'images/decoration/grass_area_${context.isDarkMode ? "dark" : "light"}.webp'),
        ),
        CustomPaint(
          painter: LandPainter(context),
          size: MediaQuery.of(context).size,
        )
      ],
    );
  }
}

class LandPainter extends CustomPainter {
  late BuildContext context;

  LandPainter(this.context);

  @override
  void paint(Canvas canvas, Size size) {
    Color grassColor =
        context.isDarkMode ? Color(0xff122a22) : Color(0xff507769);
    canvas.drawRect(
      Rect.fromLTRB(0, size.height / 2, size.width, size.height),
      Paint()..color = grassColor,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.45, size.height / 2)
        ..lineTo(0, size.height * 0.9)
        ..lineTo(0, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height * 0.9)
        ..lineTo(size.width * 0.55, size.height / 2),
      Paint()
        ..style = PaintingStyle.fill
        ..color = Theme.of(context).colorScheme.surface,
    );
  }

  @override
  bool shouldRepaint(LandPainter oldDelegate) =>
      oldDelegate.context.isDarkMode != context.isDarkMode;
}
