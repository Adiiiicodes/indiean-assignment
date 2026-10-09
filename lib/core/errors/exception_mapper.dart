import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';

AppException mapException(Object error) {
  if (error is AppException) return error;
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.transformTimeout ||
      DioExceptionType.receiveTimeout => const TimeoutAppException(),
      DioExceptionType.connectionError => const NetworkException(),
      DioExceptionType.badCertificate => const NetworkException(
        AppStrings.secureConnectionError,
      ),
      DioExceptionType.cancel => const NetworkException(
        AppStrings.requestCancelled,
      ),
      DioExceptionType.badResponse => ServerException(
        statusCode: error.response?.statusCode,
        message: error.response?.statusCode == 429
            ? AppStrings.rateLimitError
            : AppStrings.serverError,
      ),
      DioExceptionType.unknown => mapException(
        error.error is DioException
            ? const UnknownException()
            : error.error ?? error.message ?? '',
      ),
    };
  }
  if (error is SocketException) return const NetworkException();
  if (error is TimeoutException) return const TimeoutAppException();
  if (error is FileSystemException) return const StorageException();
  if (error is FormatException) {
    return const ServerException(message: AppStrings.invalidResponse);
  }
  return const UnknownException();
}
