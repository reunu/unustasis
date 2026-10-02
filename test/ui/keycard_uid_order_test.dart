import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/ui/screens/ls_keycard_screen.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('keycard hex groups retain wire order in $direction', (tester) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: [
          FlutterI18nDelegate(
            translationLoader: FileTranslationLoader(
              basePath: 'assets/i18n',
              fallbackFile: 'en',
              forcedLocale: const Locale('en'),
            ),
          ),
        ],
        home: Scaffold(
          body: Directionality(
            textDirection: direction,
            child: KeycardCard(
              index: 0,
              uid: '1234ABCD',
              alias: 'Test card',
              onDelete: (_) async {},
              onRename: (uid, alias) async {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final uid = find.text('1234 ABCD');
      expect(uid, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: uid, matching: find.byType(RichText)),
      );
      final first = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 4));
      final second = paragraph.getBoxesForSelection(const TextSelection(baseOffset: 5, extentOffset: 9));
      expect(first.single.left, lessThan(second.single.left));
      expect(tester.takeException(), isNull);
    });
  }
}
