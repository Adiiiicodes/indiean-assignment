import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:focusdesk/core/constants/app_constants.dart';

class ApiClient {
  ApiClient({
    Dio? dio,
    bool enableLogging = true,
    void Function(String)? logger,
  }) : dio = dio ?? Dio() {
    this.dio.options = this.dio.options.copyWith(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: AppConstants.networkTimeout,
      receiveTimeout: AppConstants.networkTimeout,
      responseType: ResponseType.json,
    );
    if (kDebugMode && enableLogging) {
      this.dio.interceptors.add(_MetadataLogger(logger ?? debugPrint));
    }
  }

  final Dio dio;
}

class _MetadataLogger extends Interceptor {
  _MetadataLogger(this.logger);
  final void Function(String) logger;

  void _log(String message) {
    try {
      logger(message);
    } catch (_) {
      // Optional diagnostics must never interrupt a request.
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _log('API ${options.method} ${options.uri.path}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _log('API ${response.statusCode} ${response.requestOptions.uri.path}');
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    _log('API ${error.type.name} ${error.requestOptions.uri.path}');
    handler.next(error);
  }
}
