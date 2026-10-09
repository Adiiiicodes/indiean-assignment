import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';

import 'helpers/app_dependencies.dart';

void main() {
  testWidgets('FocusDesk scaffold opens without an exception', (tester) async {
    final dependencies = await createTestDependencies();
    await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
    expect(find.text('FocusDesk'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
