import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:grund/src/app/hot_reload_extension.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';

/// The module of the application; a test changes it to "reload" the code.
final class Code {
  /// The path of the one route.
  static String path = '/a';

  /// Whether the module function throws a non-grund error.
  static bool isBroken = false;

  /// The module of the current code.
  static Module module() {
    if (isBroken) throw StateError('broken module');
    return Module(
      id: 'app',
      providers: [Provider((i) => Clock())],
      controllers: [
        Controller<Clock>(
          create: (i) => i.get(),
          routes: [Route.get(path, (c, ctx) => 'ok')],
        ),
      ],
    );
  }
}

/// An application of [Code.module] closed when the test ends.
Future<Application> started() async {
  final application = await Application.create(Code.module);
  addTearDown(application.close);
  return application;
}

/// The JSON result of calling [method], or a failure with its error.
Future<Map<String, Object?>> callExtension(String method) async {
  final response = await HotReloadExtension.handle(method, const {});
  final result =
      response.result ??
      fail('error ${response.errorCode}: ${response.errorDetail}');
  return jsonDecode(result) as Map<String, Object?>;
}

/// An adapter whose [close] fails with [label], after [delay].
final class FailingAdapter implements HttpAdapter {
  /// Creates an adapter that fails to close.
  FailingAdapter(this.label, this.delay);

  /// The text of the failure.
  final String label;

  /// How long [close] takes before it fails.
  final Duration delay;

  @override
  Future<void> listen(
    RequestHandler handler, {
    required int port,
    Object address = 'localhost',
  }) async {}

  @override
  Future<void> close({bool force = false}) async {
    await Future<void>.delayed(delay);
    throw StateError(label);
  }
}

/// A listening application whose close fails with [label] after [delay].
Future<Application> failingToClose(String label, Duration delay) async {
  final application = await Application.create(
    Code.module,
    adapter: FailingAdapter(label, delay),
  );
  await application.listen(port: 0);
  return application;
}

void main() {
  setUp(() {
    Code.path = '/a';
    Code.isBroken = false;
  });

  test('the extensions exist outside product builds', () {
    expect(HotReloadExtension.isEnabled, isTrue);
  });

  test(
    'reassemble rebuilds every open application and reports routes',
    () async {
      final first = await started();
      await started();
      Code.path = '/b';

      final result = await callExtension(HotReloadExtension.reassembleMethod);

      expect(result, {
        'applications': 2,
        'addedRoutes': ['GET /b', 'GET /b'],
        'removedRoutes': ['GET /a', 'GET /a'],
      });
      expect(first.container.graph.root.controllers, hasLength(1));
    },
  );

  test('a closed application is not reassembled', () async {
    final application = await started();
    await application.close();

    expect(await callExtension(HotReloadExtension.reassembleMethod), {
      'applications': 0,
      'addedRoutes': <String>[],
      'removedRoutes': <String>[],
    });
  });

  test('a grund error is answered with its message', () async {
    await started();
    Code.path = 'a/:x/:x';

    final response = await HotReloadExtension.handle(
      HotReloadExtension.reassembleMethod,
      const {},
    );

    expect(response.errorCode, -32000);
    expect(response.errorDetail, startsWith('InvalidRoutePatternError: '));
    expect(response.errorDetail, isNot(contains('#0')));
  });

  test('any other error is answered with its stack trace', () async {
    await started();
    Code.isBroken = true;

    final response = await HotReloadExtension.handle(
      HotReloadExtension.reassembleMethod,
      const {},
    );

    expect(response.errorDetail, startsWith('Bad state: broken module\n#0'));
  });

  test('close closes every open application', () async {
    final application = await started();

    expect(await callExtension(HotReloadExtension.closeMethod), {
      'applications': 1,
    });
    expect(application.isClosed, isTrue);
  });

  test('a failed reassemble names the application that failed', () async {
    await started();
    var broken = false;
    final second = await Application.create(() {
      if (broken) throw StateError('second is broken');
      return Code.module();
    });
    addTearDown(second.close);
    broken = true;

    final response = await HotReloadExtension.handle(
      HotReloadExtension.reassembleMethod,
      const {},
    );

    expect(
      response.errorDetail,
      startsWith('application 2 of 2: Bad state: second is broken\n#0'),
    );
  });

  test('close reports every failure in application order', () async {
    await failingToClose('first', const Duration(milliseconds: 40));
    await failingToClose('second', Duration.zero);

    final response = await HotReloadExtension.handle(
      HotReloadExtension.closeMethod,
      const {},
    );

    expect(response.errorCode, -32000);
    final detail = response.errorDetail!;
    expect(detail, contains('application 1 of 2: Bad state: first'));
    expect(detail, contains('application 2 of 2: Bad state: second'));
    expect(detail.indexOf('first'), lessThan(detail.indexOf('second')));
  });
}
