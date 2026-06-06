import 'package:alertrix_frontend/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('register form starts with send code and manual passwords',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AlertrixApp());

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('Send code'), findsOneWidget);
    expect(find.text('Resend code'), findsNothing);

    final passwordFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((field) => field.obscureText)
        .toList();

    expect(passwordFields, hasLength(2));
    for (final field in passwordFields) {
      expect(field.keyboardType, TextInputType.visiblePassword);
      expect(field.enableSuggestions, isFalse);
      expect(field.autocorrect, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.readOnly, isTrue);
      expect(
        field.autofillHints,
        orderedEquals(const [AutofillHints.newPassword]),
      );
    }

    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) => widget is TextField && widget.obscureText,
          )
          .first,
    );
    await tester.pump();

    final unlockedPasswordFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((field) => field.obscureText)
        .toList();

    expect(unlockedPasswordFields.first.readOnly, isFalse);
    expect(unlockedPasswordFields.last.readOnly, isTrue);
  });
}
