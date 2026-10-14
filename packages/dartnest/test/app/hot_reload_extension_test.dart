import 'dart:convert';

import 'package:dartnest/dartnest.dart';
import 'package:dartnest/src/app/hot_reload_extension.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';

/// The module of the application; a test changes it to "reload" the code.
final class Code {
  /// The path of the one route.
  static String path = '/a';

  /// Whether the module function throws a non-dartnest error.
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

  test('a dartnest error is answered with its message', () async {
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
}
