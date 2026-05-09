import 'package:flutter_test/flutter_test.dart';

import 'package:alertrix_frontend/app.dart';

void main() {
  testWidgets('login page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const AlertrixApp());

    expect(find.text('Alertrix Login'), findsOneWidget);
    expect(find.text('Enter Dashboard'), findsOneWidget);
  });
}
