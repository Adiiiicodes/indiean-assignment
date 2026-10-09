import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/main.dart';

void main() {
  testWidgets('FocusDesk scaffold opens without an exception', (tester) async {
    await tester.pumpWidget(const FocusDeskApp());
    expect(find.text('FocusDesk'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
