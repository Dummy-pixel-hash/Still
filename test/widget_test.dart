import 'package:flutter_test/flutter_test.dart';
import 'package:still/src/app.dart';

void main() {
  testWidgets('Spike screen boots with terminal + connect',
      (WidgetTester tester) async {
    await tester.pumpWidget(const StillApp());
    await tester.pumpAndSettle();
    expect(find.text('Still — terminal/runtime spike (M1)'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });
}
