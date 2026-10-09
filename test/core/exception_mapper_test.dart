import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';

const _rawDetail = 'Private transport detail containing test-secret';

DioException _transportError(
  DioExceptionType type, {
  Object? cause,
  int? status,
}) {
  final request = RequestOptions(
    path: 'https://example.invalid/private?token=test-secret',
    headers: {'Authorization': 'Bearer test-secret'},
  );
  return DioException(
    requestOptions: request,
    type: type,
    error: cause,
    message: _rawDetail,
    response: status == null
        ? null
        : Response(
            requestOptions: request,
            statusCode: status,
            data: {'debug': _rawDetail},
          ),
  );
}

void main() {
  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.transformTimeout,
  ]) {
    test('${type.name} has a friendly timeout message', () {
      final mapped = mapException(_transportError(type));
      expect(mapped, isA<TimeoutAppException>());
      expect(mapped.message, AppStrings.timeoutError);
      expect(mapped.toString(), isNot(contains('test-secret')));
    });
  }

  for (final (type, message) in [
    (DioExceptionType.connectionError, AppStrings.networkError),
    (DioExceptionType.badCertificate, AppStrings.secureConnectionError),
    (DioExceptionType.cancel, AppStrings.requestCancelled),
  ]) {
    test('${type.name} explains the failure without transport details', () {
      final mapped = mapException(_transportError(type));
      expect(mapped, isA<NetworkException>());
      expect(mapped.message, message);
      expect(mapped.toString(), isNot(contains('test-secret')));
    });
  }

  for (final (status, message) in [
    (500, AppStrings.serverError),
    (429, AppStrings.rateLimitError),
  ]) {
    test('HTTP $status preserves status with a friendly message', () {
      final mapped = mapException(
        _transportError(DioExceptionType.badResponse, status: status),
      );
      expect(mapped, isA<ServerException>());
      expect((mapped as ServerException).statusCode, status);
      expect(mapped.message, message);
      expect(mapped.toString(), isNot(contains('test-secret')));
    });
  }

  final causes = <(Object, Type, String)>[
    (
      const SocketException(_rawDetail),
      NetworkException,
      AppStrings.networkError,
    ),
    (
      TimeoutException(_rawDetail),
      TimeoutAppException,
      AppStrings.timeoutError,
    ),
    (
      const FormatException(_rawDetail),
      ServerException,
      AppStrings.invalidResponse,
    ),
    (
      const FileSystemException(_rawDetail, '/private/test-secret/data'),
      StorageException,
      AppStrings.storageError,
    ),
    (StateError(_rawDetail), UnknownException, AppStrings.unknownError),
  ];

  for (final (cause, expectedType, message) in causes) {
    test(
      '${cause.runtimeType} maps directly and through unknown Dio errors',
      () {
        for (final error in [
          cause,
          _transportError(DioExceptionType.unknown, cause: cause),
        ]) {
          final mapped = mapException(error);
          expect(mapped.runtimeType, expectedType);
          expect(mapped.message, message);
          expect(mapped.toString(), isNot(contains('test-secret')));
        }
      },
    );
  }

  test('unknown Dio messages and nested transport errors stay private', () {
    for (final error in [
      _transportError(DioExceptionType.unknown),
      _transportError(
        DioExceptionType.unknown,
        cause: _transportError(DioExceptionType.connectionError),
      ),
    ]) {
      final mapped = mapException(error);
      expect(mapped, isA<UnknownException>());
      expect(mapped.message, AppStrings.unknownError);
      expect(mapped.toString(), isNot(contains('test-secret')));
    }
  });

  test('existing application exceptions retain their identity and message', () {
    for (final error in [
      const ValidationException('Check the task title.'),
      const ServerException(statusCode: 503, message: 'Try again later.'),
      const MediaException(),
    ]) {
      expect(mapException(error), same(error));
    }
  });
}
