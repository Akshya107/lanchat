import 'package:flutter_test/flutter_test.dart';
import 'package:lanchat_mobile/main.dart';
import 'package:lanchat_mobile/policy_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first launch shows directive before the gate', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LanchatApp());
    await tester.pump();
    expect(find.text('ACCEPT'), findsOneWidget);
    expect(find.textContaining('DIRECTIVE'), findsWidgets);
    expect(find.textContaining('NOT responsible'), findsOneWidget);
  });

  testWidgets('accepted policy shows chrono gate', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({policyPrefKey: policyVersion});
    await tester.pumpWidget(const LanchatApp());
    await tester.pump();
    expect(find.textContaining('CHRONO GATE'), findsOneWidget);
    expect(find.text('OPEN LATTICE'), findsOneWidget);
  });
}
