import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';
import 'package:focusdesk/data/models/suggested_page_model.dart';

class SuggestedRepository {
  SuggestedRepository(this._datasource);
  final SuggestedRemoteDatasource _datasource;

  Future<SuggestedPageModel> fetch({
    int limit = AppConstants.pageSize,
    int skip = 0,
  }) async {
    try {
      return await _datasource.fetchTodos(limit: limit, skip: skip);
    } catch (error) {
      throw mapException(error);
    }
  }
}
