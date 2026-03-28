import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gsrapp/app.dart';

void main() {
  testWidgets('app boots successfully', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'has_opened_before': true,
      'display_name': 'demo',
      'email': 'demo@health.local',
    });

    await tester.pumpWidget(const MyApp(initializeFirebase: false));

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(MyApp).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.byType(MyApp), findsOneWidget);
  });
}
