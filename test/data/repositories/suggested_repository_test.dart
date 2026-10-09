import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';
import 'package:focusdesk/data/models/suggested_page_model.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';

class _Remote extends SuggestedRemoteDatasource {
  _Remote() : super(Dio());
  final requests = <(int, int)>[];
  Object? failure;
  late SuggestedPageModel page;

  @override
  Future<SuggestedPageModel> fetchTodos({int limit = 20, int skip = 0}) async {
    requests.add((limit, skip));
    if (failure != null) throw failure!;
    return page;
  }
}

void main() {
  late _Remote remote;
  late SuggestedRepository repository;

  setUp(() {
    remote = _Remote()
      ..page = SuggestedPageModel(
        todos: const [
          SuggestedTaskModel(
            id: 1,
            todo: 'Review the release',
            completed: false,
            userId: 7,
          ),
        ],
        total: 1,
        skip: 0,
        limit: 20,
      );
    repository = SuggestedRepository(remote);
  });

  test(
    'default fetch forwards pagination and preserves the parsed domain page',
    () async {
      expect(await repository.fetch(), same(remote.page));
      expect(remote.requests, [(20, 0)]);
    },
  );

  test('custom fetch forwards its exact limit and offset', () async {
    remote.page = SuggestedPageModel(
      todos: const [
        SuggestedTaskModel(
          id: 3,
          todo: 'Task three',
          completed: true,
          userId: 7,
        ),
        SuggestedTaskModel(
          id: 4,
          todo: 'Task four',
          completed: false,
          userId: 7,
        ),
      ],
      total: 4,
      skip: 2,
      limit: 2,
    );
    final page = await repository.fetch(limit: 2, skip: 2);
    expect(remote.requests, [(2, 2)]);
    expect(page, same(remote.page));
    expect(page.hasMore, isFalse);
  });

  test(
    'existing friendly datasource failures retain identity and status',
    () async {
      const failure = ServerException(
        statusCode: 429,
        message: AppStrings.rateLimitError,
      );
      remote.failure = failure;
      await expectLater(repository.fetch(), throwsA(same(failure)));
      expect(remote.requests, [(20, 0)]);
    },
  );

  test(
    'unexpected parse and transport failures map without exposing raw details',
    () async {
      remote.failure = const FormatException('test-secret');
      await expectLater(
        repository.fetch(),
        throwsA(
          isA<ServerException>().having(
            (error) => error.message,
            'message',
            AppStrings.invalidResponse,
          ),
        ),
      );
      remote.failure = DioException(
        requestOptions: RequestOptions(path: '/todos'),
        type: DioExceptionType.receiveTimeout,
        message: 'test-secret',
      );
      await expectLater(
        repository.fetch(),
        throwsA(
          isA<TimeoutAppException>().having(
            (error) => error.message,
            'message',
            AppStrings.timeoutError,
          ),
        ),
      );
      remote.failure = StateError('test-secret');
      await expectLater(
        repository.fetch(),
        throwsA(
          isA<UnknownException>()
              .having(
                (error) => error.message,
                'message',
                AppStrings.unknownError,
              )
              .having(
                (error) => error.toString(),
                'private data',
                isNot(contains('test-secret')),
              ),
        ),
      );
    },
  );
}
