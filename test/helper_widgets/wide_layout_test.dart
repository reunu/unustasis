import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/helper_widgets/wide_layout.dart';

Widget _host(Size size, Widget child) => MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

void main() {
  testWidgets('page content is inset only above the wide-display breakpoint', (tester) async {
    late EdgeInsets narrow;
    late EdgeInsets wide;
    await tester.pumpWidget(
      Column(
        children: [
          _host(const Size(400, 800), Builder(builder: (context) {
            narrow = wideContentPadding(context);
            return const SizedBox.shrink();
          })),
          _host(const Size(1200, 800), Builder(builder: (context) {
            wide = wideContentPadding(context);
            return const SizedBox.shrink();
          })),
        ],
      ),
    );

    expect(narrow, EdgeInsets.zero);
    expect(wide, const EdgeInsets.symmetric(horizontal: 80));
  });

  testWidgets('the base padding survives the wide inset', (tester) async {
    const base = EdgeInsets.fromLTRB(16, 0, 16, 24);
    late EdgeInsets narrow;
    late EdgeInsets wide;
    await tester.pumpWidget(
      Column(
        children: [
          _host(const Size(400, 800), Builder(builder: (context) {
            narrow = wideContentPadding(context, base: base);
            return const SizedBox.shrink();
          })),
          _host(const Size(1200, 800), Builder(builder: (context) {
            wide = wideContentPadding(context, base: base);
            return const SizedBox.shrink();
          })),
        ],
      ),
    );

    expect(narrow, base);
    expect(wide, const EdgeInsets.fromLTRB(96, 0, 96, 24));
  });

  test('the wide-display breakpoint matches the layout contract', () {
    expect(wideDisplayBreakpoint, 600);
    expect(wideDialogConstraints.maxWidth, 600);
  });

  test('dialogs and bottom sheets are capped in both themes', () {
    final source = File('lib/ui/theme/app_theme.dart').readAsStringSync();
    expect(
      'dialogTheme: const DialogThemeData(constraints: wideDialogConstraints),'.allMatches(source),
      hasLength(2),
    );
    expect(
      'bottomSheetTheme: const BottomSheetThemeData(constraints: wideDialogConstraints),'.allMatches(source),
      hasLength(2),
    );
  });

  testWidgets('WideContent centres and caps its child', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: WideContent(maxWidth: 600, child: Text('content')),
      ),
    );

    final box = tester.getSize(find.byType(Text));
    // The text is laid out inside the cap and the whole block is centred.
    final centre = tester.getCenter(find.byType(Text)).dx;
    expect(centre, closeTo(600, 1));
    expect(box.width, lessThanOrEqualTo(600));
  });
}
