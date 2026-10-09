import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/data/models/user_model.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 9, 14, 30);
  final user = UserModel(
    id: 'user-1',
    name: 'Aditya',
    email: 'aditya@example.com',
    createdAt: createdAt,
  );

  test('UserModel round trips through JSON with an ISO date', () {
    final encoded = jsonEncode(user.toJson());
    final restored = UserModel.fromJson(
      jsonDecode(encoded) as Map<String, dynamic>,
    );
    expect(restored, user);
    expect(restored.createdAt.isUtc, isTrue);
    expect(user.toJson(), {
      'id': 'user-1',
      'name': 'Aditya',
      'email': 'aditya@example.com',
      'createdAt': '2026-10-09T14:30:00.000Z',
    });
  });

  test('copyWith preserves unchanged fields and does not mutate original', () {
    final renamed = user.copyWith(name: 'Ada');
    expect(renamed.name, 'Ada');
    expect(renamed.id, user.id);
    expect(renamed.email, user.email);
    expect(renamed.createdAt, user.createdAt);
    expect(user.name, 'Aditya');
    expect(user.copyWith(), user);
  });

  test('copyWith can replace each field', () {
    final otherDate = DateTime.utc(2027, 1, 1);
    final updated = user.copyWith(
      id: 'user-2',
      name: 'Ada',
      email: 'ada@example.com',
      createdAt: otherDate,
    );
    expect(updated.id, 'user-2');
    expect(updated.name, 'Ada');
    expect(updated.email, 'ada@example.com');
    expect(updated.createdAt, otherDate);
  });

  test('equality and hashCode include every field', () {
    final same = UserModel.fromJson(user.toJson());
    expect(same, user);
    expect(same.hashCode, user.hashCode);
    expect(user.copyWith(id: 'other'), isNot(user));
    expect(user.copyWith(name: 'Other'), isNot(user));
    expect(user.copyWith(email: 'other@example.com'), isNot(user));
    expect(
      user.copyWith(createdAt: createdAt.add(const Duration(seconds: 1))),
      isNot(user),
    );
  });

  for (final field in ['id', 'name', 'email', 'createdAt']) {
    test('rejects missing $field with FormatException', () {
      final json = user.toJson()..remove(field);
      expect(() => UserModel.fromJson(json), throwsFormatException);
    });

    test('rejects invalid type and blank $field with FormatException', () {
      for (final badValue in [null, 12, true, '', '   ']) {
        final json = user.toJson()..[field] = badValue;
        expect(() => UserModel.fromJson(json), throwsFormatException);
      }
    });
  }

  test('rejects an unparseable creation date', () {
    final json = user.toJson()..['createdAt'] = 'not-a-date';
    expect(() => UserModel.fromJson(json), throwsFormatException);
  });
}
