import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/theme/app_theme.dart';
import 'package:unustasis/ui/widgets/primary_button.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('shared primary button keeps Stasis setup styling in ${dark ? 'dark' : 'light'} mode', (tester) async {
      final theme = dark ? unustasisDarkTheme() : unustasisLightTheme();
      var pressed = 0;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
            body: PrimaryButton(
                text: 'Continue',
                icon: Icons.arrow_forward,
                onPressed: () {
                  pressed++;
                })),
      ));
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.style!.backgroundColor!.resolve({}), theme.colorScheme.onSurface);
      expect(button.style!.foregroundColor!.resolve({}), theme.colorScheme.onTertiary);
      expect(button.style!.minimumSize!.resolve({}), const Size.fromHeight(60));
      expect(button.style!.shape, isNull, reason: 'Rounding belongs to the existing app theme, not this feature');
      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(find.text('Continue'));
      expect(pressed, 1);
    });
  }

  testWidgets('a busy primary button keeps the action disabled', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: unustasisLightTheme(),
      home: Scaffold(
          body: PrimaryButton(
              text: 'Continue',
              busy: true,
              onPressed: () {
                pressed++;
              })),
    ));
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Continue'));
    expect(pressed, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
