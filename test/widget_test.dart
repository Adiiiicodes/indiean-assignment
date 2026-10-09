import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';

import 'helpers/app_dependencies.dart';

void main() {
  testWidgets('FocusDesk shows its splash then opens login', (tester) async {
    final dependencies = await createTestDependencies();
    await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text(AppStrings.appName), findsWidgets);
    expect(find.text(AppStrings.tagline), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
