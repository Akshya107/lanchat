import 'package:flutter_test/flutter_test.dart';
import 'package:lanchat_mobile/main.dart';

void main() {
  testWidgets('gate screen asks for operator name', (WidgetTester tester) async {
    await tester.pumpWidget(const LanchatApp());
    expect(find.text('NEURAL GATE'), findsOneWidget);
    expect(find.text('OPEN UPLINK'), findsOneWidget);
  });
}
