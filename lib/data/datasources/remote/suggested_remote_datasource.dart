import 'package:dio/dio.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/suggested_page_model.dart';

class SuggestedRemoteDatasource {
  SuggestedRemoteDatasource(this._dio);
  final Dio _dio;

  Future<SuggestedPageModel> fetchTodos({
    int limit = AppConstants.pageSize,
    int skip = 0,
  }) async {
    try {
      if (limit <= 0 || skip < 0) {
        throw const FormatException('Invalid requested pagination.');
      }
      final response = await _dio.get<dynamic>(
        '/todos',
        queryParameters: {'limit': limit, 'skip': skip},
      );
      final status = response.statusCode;
      if (status == null || status < 200 || status >= 300) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
        );
      }
      final json = response.data;
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Invalid suggested response object.');
      }
      final page = SuggestedPageModel.fromJson(json);
      if (page.skip != skip || page.limit > limit) {
        throw const FormatException('Unexpected suggested pagination.');
      }
      return page;
    } on AppException {
      rethrow;
    } catch (error) {
      throw mapException(error);
    }
  }
}
