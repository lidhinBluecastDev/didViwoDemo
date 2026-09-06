import 'package:flutter_test/flutter_test.dart';

import 'package:did_webrtc_test/main.dart';

void main() {
  testWidgets('Welcome screen shows Talk to teacher', (tester) async {
    await tester.pumpWidget(const ViwoSchoolApp());
    expect(find.text('Talk to teacher'), findsOneWidget);
  });
}
