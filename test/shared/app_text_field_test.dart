import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/utils/validators.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

Future<void> _pumpField(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('form validates edits and submits keyboard input', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    String? changed;
    String? submitted;
    await _pumpField(
      tester,
      Form(
        key: formKey,
        child: AppTextField(
          label: AppStrings.email,
          hint: AppStrings.emailHint,
          validator: Validators.email,
          prefixIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.email],
          onChanged: (value) => changed = value,
          onFieldSubmitted: (value) => submitted = value,
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text(AppStrings.emailRequired), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text(AppStrings.emailInvalid), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'demo@focusdesk.app');
    expect(formKey.currentState!.validate(), isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(changed, 'demo@focusdesk.app');
    expect(submitted, 'demo@focusdesk.app');
    expect(find.text(AppStrings.emailInvalid), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('password visibility preserves input in ${brightness.name}', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pumpField(
        tester,
        AppTextField(
          label: AppStrings.password,
          controller: controller,
          isPassword: true,
          maxLines: 3,
          prefixIcon: Icons.lock_outline,
        ),
        brightness: brightness,
      );

      await tester.enterText(find.byType(TextFormField), 'Focus@123');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip(AppStrings.showPassword));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isFalse,
      );
      expect(controller.text, 'Focus@123');
      await tester.tap(find.byTooltip(AppStrings.hidePassword));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
      expect(controller.text, 'Focus@123');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('initial value supports multiline editing and a custom suffix', (
    tester,
  ) async {
    await _pumpField(
      tester,
      const AppTextField(
        label: AppStrings.description,
        initialValue: 'First line',
        maxLines: 3,
        maxLength: 300,
        suffixIcon: Icon(Icons.notes_outlined),
        textInputAction: TextInputAction.newline,
      ),
    );
    expect(find.text('First line'), findsOneWidget);
    expect(find.byIcon(Icons.notes_outlined), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      'First line\nSecond line',
    );
    await tester.pump();
    expect(find.text('First line\nSecond line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
