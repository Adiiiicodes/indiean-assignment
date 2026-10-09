import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/remote/api_client.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';

const _todo = {
  'id': 42,
  'todo': 'Review the release',
  'completed': false,
  'userId': 7,
};
const _page = {
  'todos': [_todo],
  'total': 1,
  'skip': 0,
  'limit': 20,
};

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final FutureOr<ResponseBody> Function(RequestOptions) reply;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(Object? data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

(Dio, _Adapter, SuggestedRemoteDatasource) _source(
  FutureOr<ResponseBody> Function(RequestOptions) reply, {
  bool logging = false,
  void Function(String)? logger,
}) {
  final dio = ApiClient(enableLogging: logging, logger: logger).dio;
  final adapter = _Adapter(reply);
  dio.httpClientAdapter = adapter;
  addTearDown(() => dio.close(force: true));
  return (dio, adapter, SuggestedRemoteDatasource(dio));
}

Matcher _invalidResponse() => isA<ServerException>()
    .having(
      (error) => error.message,
      'friendly message',
      AppStrings.invalidResponse,
    )
    .having(
      (error) => error.toString(),
      'private data',
      isNot(contains('test-secret')),
    );

void main() {
  test(
    'configured client preserves injected Dio and uses the API defaults',
    () {
      final injected = Dio();
      final adapter = _Adapter((_) => _response(_page));
      injected.httpClientAdapter = adapter;
      final client = ApiClient(dio: injected, enableLogging: false);
      addTearDown(() => injected.close(force: true));
      expect(client.dio, same(injected));
      expect(client.dio.httpClientAdapter, same(adapter));
      expect(client.dio.options.baseUrl, AppConstants.apiBaseUrl);
      expect(client.dio.options.connectTimeout, const Duration(seconds: 10));
      expect(client.dio.options.receiveTimeout, const Duration(seconds: 10));
      expect(client.dio.options.responseType, ResponseType.json);
    },
  );

  test(
    'success parses page fields and sends the requested limit and skip',
    () async {
      final (_, adapter, source) = _source(
        (_) => _response({
          'todos': [
            _todo,
            {..._todo, 'id': 43, 'completed': true},
          ],
          'total': 5,
          'skip': 2,
          'limit': 2,
        }),
      );
      final page = await source.fetchTodos(limit: 2, skip: 2);
      expect(page.todos.map((todo) => todo.id), [42, 43]);
      expect(page.todos.last.completed, isTrue);
      expect(page.total, 5);
      expect(page.skip, 2);
      expect(page.limit, 2);
      expect(page.hasMore, isTrue);
      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.origin, AppConstants.apiBaseUrl);
      expect(request.uri.path, '/todos');
      expect(request.queryParameters, {'limit': 2, 'skip': 2});
    },
  );

  test('default request accepts an empty result page', () async {
    final (_, adapter, source) = _source(
      (_) => _response({'todos': [], 'total': 0, 'skip': 0, 'limit': 20}),
    );
    final page = await source.fetchTodos();
    expect(page.todos, isEmpty);
    expect(page.hasMore, isFalse);
    expect(adapter.requests.single.queryParameters, {'limit': 20, 'skip': 0});
  });

  test('malformed JSON is a friendly invalid-response failure', () async {
    final (_, _, source) = _source(
      (_) => ResponseBody.fromString(
        '{test-secret',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    await expectLater(source.fetchTodos(), throwsA(_invalidResponse()));
  });

  test(
    'final page accepts the API reduced limit and stops pagination',
    () async {
      final (_, adapter, source) = _source(
        (_) => _response({
          'todos': [
            for (var id = 241; id <= 254; id++) {..._todo, 'id': id},
          ],
          'total': 254,
          'skip': 240,
          'limit': 14,
        }),
      );
      final page = await source.fetchTodos(limit: 20, skip: 240);
      expect(page.todos, hasLength(14));
      expect(page.limit, 14);
      expect(page.hasMore, isFalse);
      expect(adapter.requests.single.queryParameters, {
        'limit': 20,
        'skip': 240,
      });
    },
  );

  test('beyond-total empty page accepts the API zero returned limit', () async {
    final (_, _, source) = _source(
      (_) => _response({'todos': [], 'total': 254, 'skip': 260, 'limit': 0}),
    );
    final page = await source.fetchTodos(limit: 20, skip: 260);
    expect(page.todos, isEmpty);
    expect(page.limit, 0);
    expect(page.hasMore, isFalse);
  });

  test(
    'response pagination must match its requested offset and limit ceiling',
    () async {
      for (final invalid in [
        {..._page, 'skip': 1, 'total': 2},
        {..._page, 'limit': 21},
      ]) {
        final (_, _, source) = _source((_) => _response(invalid));
        await expectLater(source.fetchTodos(), throwsA(_invalidResponse()));
      }
    },
  );

  for (final invalid in [
    null,
    [],
    'test-secret',
    42,
    {'todos': [], 'total': 0},
  ]) {
    test('rejects malformed response body $invalid', () async {
      final (_, _, source) = _source((_) => _response(invalid));
      await expectLater(source.fetchTodos(), throwsA(_invalidResponse()));
    });
  }

  test('malformed item and page metadata reject the whole response', () async {
    for (final invalid in [
      {
        ..._page,
        'todos': [
          {..._todo, 'completed': 'false'},
        ],
      },
      {
        ..._page,
        'todos': [null],
      },
      {..._page, 'total': -1},
      {..._page, 'skip': '0'},
      {..._page, 'limit': 0},
      {
        ..._page,
        'todos': [_todo, _todo],
        'total': 2,
      },
      {..._page, 'total': 0},
      {..._page, 'total': 30},
      {..._page, 'todos': [], 'limit': 0},
    ]) {
      final (_, _, source) = _source((_) => _response(invalid));
      await expectLater(
        source.fetchTodos(),
        throwsA(_invalidResponse()),
        reason: invalid.toString(),
      );
    }
  });

  test('invalid pagination is rejected before any network request', () async {
    final (_, adapter, source) = _source((_) => _response(_page));
    for (final (limit, skip) in [(0, 0), (-1, 0), (20, -1)]) {
      await expectLater(
        source.fetchTodos(limit: limit, skip: skip),
        throwsA(_invalidResponse()),
      );
    }
    expect(adapter.requests, isEmpty);
  });

  for (final (status, message) in [
    (500, AppStrings.serverError),
    (429, AppStrings.rateLimitError),
  ]) {
    test('HTTP$status preserves its code with a friendly message', () async {
      final (_, _, source) = _source(
        (_) => _response({'error': 'test-secret'}, status: status),
      );
      await expectLater(
        source.fetchTodos(),
        throwsA(
          isA<ServerException>()
              .having((error) => error.statusCode, 'status', status)
              .having((error) => error.message, 'message', message)
              .having(
                (error) => error.toString(),
                'private data',
                isNot(contains('test-secret')),
              ),
        ),
      );
    });
  }

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.transformTimeout,
  ]) {
    test('${type.name} maps to a friendly timeout', () async {
      final (_, _, source) = _source(
        (options) => throw DioException(
          requestOptions: options,
          type: type,
          message: 'test-secret',
        ),
      );
      await expectLater(
        source.fetchTodos(),
        throwsA(
          isA<TimeoutAppException>().having(
            (error) => error.message,
            'message',
            AppStrings.timeoutError,
          ),
        ),
      );
    });
  }

  test(
    'HTTP failure maps even when injected validateStatus accepts every status',
    () async {
      final (dio, _, source) = _source(
        (_) => _response({'error': 'test-secret'}, status: 500),
      );
      dio.options.validateStatus = (_) => true;
      await expectLater(
        source.fetchTodos(),
        throwsA(
          isA<ServerException>()
              .having((error) => error.statusCode, 'status', 500)
              .having(
                (error) => error.message,
                'message',
                AppStrings.serverError,
              ),
        ),
      );
    },
  );

  test('connection failure maps without leaking transport details', () async {
    final (_, _, source) = _source(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        error: const SocketException('test-secret'),
        message: 'test-secret',
      ),
    );
    await expectLater(
      source.fetchTodos(),
      throwsA(
        isA<NetworkException>()
            .having(
              (error) => error.message,
              'message',
              AppStrings.networkError,
            )
            .having(
              (error) => error.toString(),
              'private data',
              isNot(contains('test-secret')),
            ),
      ),
    );
  });

  test('wrapped socket failure is also a friendly network error', () async {
    final (_, _, source) = _source(
      (options) => throw DioException(
        requestOptions: options,
        error: const SocketException('test-secret'),
      ),
    );
    await expectLater(
      source.fetchTodos(),
      throwsA(
        isA<NetworkException>().having(
          (error) => error.message,
          'message',
          AppStrings.networkError,
        ),
      ),
    );
  });

  test('disabled logging records no request or response metadata', () async {
    final logs = <String>[];
    final (_, _, source) = _source((_) => _response(_page), logger: logs.add);
    await source.fetchTodos();
    expect(logs, isEmpty);
  });

  test(
    'debug logging contains metadata while excluding headers and bodies',
    () async {
      final logs = <String>[];
      final (dio, _, _) = _source(
        (_) => _response({'private': 'test-secret'}),
        logging: true,
        logger: logs.add,
      );
      await dio.post<Object?>(
        '/todos',
        queryParameters: {'token': 'test-secret'},
        data: {'private': 'test-secret'},
        options: Options(headers: {'Authorization': 'Bearer test-secret'}),
      );
      expect(logs, isNotEmpty);
      expect(logs.join('\n'), isNot(contains('test-secret')));
      expect(logs.join('\n'), isNot(contains('Authorization')));
      expect(logs.join('\n'), isNot(contains('private')));
    },
  );

  test('optional logging failures cannot break a valid request', () async {
    final (_, _, source) = _source(
      (_) => _response(_page),
      logging: true,
      logger: (_) => throw StateError('test-secret'),
    );
    final page = await source.fetchTodos();
    expect(page.todos.single.id, 42);
  });
}
