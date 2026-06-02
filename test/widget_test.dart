import 'package:flutter_test/flutter_test.dart';

import 'package:alertrix_frontend/app.dart';

void main() {
  testWidgets('login page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const AlertrixApp());

    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Sign in'), findsWidgets);
  });
}
