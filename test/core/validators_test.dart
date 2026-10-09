import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/utils/validators.dart';

void main() {
  group('email', () {
    test('accepts ordinary, plus-addressed and trimmed addresses', () {
      for (final value in [
        'demo@focusdesk.app',
        'Person+work@sub.example.com',
        '  person@example.com  ',
      ]) {
        expect(Validators.email(value), isNull, reason: value);
      }
    });

    test('requires a value', () {
      for (final value in [null, '', ' \t\n ']) {
        expect(Validators.email(value), AppStrings.emailRequired);
      }
    });

    test('rejects whitespace, missing domains and malformed domains', () {
      for (final value in [
        'person',
        '@example.com',
        'person@',
        'person@localhost',
        'person @example.com',
        'person@example .com',
        'person@@example.com',
        'person@.example.com',
        'person@example..com',
        'person@-example.com',
      ]) {
        expect(Validators.email(value), AppStrings.emailInvalid, reason: value);
      }
    });
  });

  group('password', () {
    test('accepts eight characters containing a letter and a number', () {
      expect(Validators.password('abcdefg1'), isNull);
      expect(Validators.password('Focus@123'), isNull);
    });

    test('requires a value and enforces length and character classes', () {
      expect(Validators.password(null), AppStrings.passwordRequired);
      expect(Validators.password(''), AppStrings.passwordRequired);
      for (final value in ['abcdef1', 'abcdefgh', '12345678', '        ']) {
        expect(Validators.password(value), AppStrings.passwordInvalid);
      }
    });

    test('preserves significant password spaces', () {
      expect(Validators.password('ab12   '), AppStrings.passwordInvalid);
      expect(Validators.password('ab12    '), isNull);
    });
  });

  test('required text rejects blank values and uses the supplied label', () {
    for (final value in [null, '', ' \t ']) {
      expect(
        Validators.requiredText(value),
        AppStrings.requiredField(AppStrings.fieldLabel),
      );
      expect(
        Validators.requiredText(value, label: 'Subject'),
        AppStrings.requiredField('Subject'),
      );
    }
    expect(Validators.requiredText('  Something  '), isNull);
  });

  test('name requires two non-padding characters', () {
    for (final value in [null, '', '  ']) {
      expect(Validators.name(value), AppStrings.nameRequired);
    }
    expect(Validators.name(' A '), AppStrings.nameInvalid);
    expect(Validators.name(' Al '), isNull);
    expect(Validators.name('Demo User'), isNull);
  });

  test(
    'task title trims padding and accepts only lengths three through eighty',
    () {
      for (final value in [null, '', '\n ']) {
        expect(Validators.taskTitle(value), AppStrings.titleRequired);
      }
      expect(Validators.taskTitle(' ab '), AppStrings.titleInvalid);
      expect(Validators.taskTitle(' abc '), isNull);
      expect(Validators.taskTitle(' ${''.padRight(80, 'a')} '), isNull);
      expect(
        Validators.taskTitle(''.padRight(81, 'a')),
        AppStrings.titleInvalid,
      );
    },
  );

  test(
    'description is optional and counts all raw characters up to three hundred',
    () {
      expect(Validators.description(null), isNull);
      expect(Validators.description(''), isNull);
      expect(Validators.description(''.padRight(300, 'a')), isNull);
      expect(
        Validators.description('${''.padRight(300, 'a')} '),
        AppStrings.descriptionInvalid,
      );
    },
  );

  test('confirmation is required and compares passwords exactly', () {
    expect(
      Validators.confirmPassword(null, 'Focus@123'),
      AppStrings.confirmPasswordRequired,
    );
    expect(
      Validators.confirmPassword('', 'Focus@123'),
      AppStrings.confirmPasswordRequired,
    );
    expect(Validators.confirmPassword('Focus@123', 'Focus@123'), isNull);
    for (final value in ['focus@123', ' Focus@123', 'Focus@123 ']) {
      expect(
        Validators.confirmPassword(value, 'Focus@123'),
        AppStrings.passwordsDoNotMatch,
      );
    }
    expect(Validators.confirmPassword('ab12    ', 'ab12    '), isNull);
  });
}
