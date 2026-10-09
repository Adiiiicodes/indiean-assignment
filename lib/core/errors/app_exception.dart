import 'package:focusdesk/core/constants/app_strings.dart';

sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class NetworkException extends AppException {
  const NetworkException([super.message = AppStrings.networkError]);
}

final class TimeoutAppException extends AppException {
  const TimeoutAppException([super.message = AppStrings.timeoutError]);
}

final class ServerException extends AppException {
  const ServerException({
    this.statusCode,
    String message = AppStrings.serverError,
  }) : super(message);
  final int? statusCode;
}

final class StorageException extends AppException {
  const StorageException([super.message = AppStrings.storageError]);
}

final class ValidationException extends AppException {
  const ValidationException(super.message);
}

final class MediaException extends AppException {
  const MediaException([super.message = AppStrings.mediaError]);
}

final class UnknownException extends AppException {
  const UnknownException([super.message = AppStrings.unknownError]);
}
