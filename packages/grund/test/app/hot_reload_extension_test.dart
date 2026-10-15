import 'dart:convert';

import 'package:grund/grund.dart';
import 'package:grund/src/app/hot_reload_extension.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';

/// The code of the application; a test changes it to "reload" the code.
final class Code {
  static String route = 'GET /a';
  static bool isBroken = false;
  static bool isInvalid = false;

  static List<Binding<Object>> bindings() {
    if (isBroken) throw StateError('broken module');
    return [
      runnerBinding(WebRunner()),
      if (isInvalid)
        Singleton<Repo>((i) => Repo(i()), dependsOn: const [Key<Clock>()]),
    ];
  }
}

/// Reports the route of the code that is current when it is reassembled.
final class WebRunner extends FakeRunner {
  WebRunner() : super('web', []);

  @override
  Future<ReassembleReport> reassemble(Injector injector) async =>
      ReassembleReport(added: [Code.route]);
}

final class CodeModule extends StubModule {
  const CodeModule();

  @override
  List<Binding<Object>> get bindings => Code.bindings();
}

Future<App> started() async {
  final app = App(root: const CodeModule());
  await app.start();
  addTearDown(app.close);
  return app;
}

Future<Map<String, Object?>> callExtension(String method) async {
  final response = await HotReloadExtension.handle(method, const {});
  final result =
      response.result ??
      fail('error ${response.errorCode}: ${response.errorDetail}');
  return jsonDecode(result) as Map<String, Object?>;
}

Future<String> failureOf(String method) async {
  final response = await HotReloadExtension.handle(method, const {});
  return response.errorDetail ??
      fail('expected an error, got ${response.result}');
}

void main() {
  setUp(() {
    Code.route = 'GET /a';
    Code.isBroken = false;
    Code.isInvalid = false;
  });

  test('the extensions exist outside product builds', () {
    expect(HotReloadExtension.isEnabled, isTrue);
  });

  test(
    'reassemble rebuilds every open application and merges the reports',
    () async {
      await started();
      await started();
      Code.route = 'GET /b';

      final result = await callExtension(HotReloadExtension.reassembleMethod);

      expect(result, {
        'applications': 2,
        'added': ['GET /b', 'GET /b'],
        'removed': <String>[],
      });
    },
  );

  test('a closed application is not reassembled', () async {
    final app = await started();
    await app.close();

    expect(await callExtension(HotReloadExtension.reassembleMethod), {
      'applications': 0,
      'added': <String>[],
      'removed': <String>[],
    });
  });

  test(
    'a failing reassemble becomes an extension error with the stack trace',
    () async {
      await started();
      Code.isBroken = true;

      final detail = await failureOf(HotReloadExtension.reassembleMethod);

      expect(detail, contains('broken module'));
      expect(detail, contains('hot_reload_extension_test.dart'));
    },
  );

  test('a GrundError is reported without a stack trace', () async {
    final app = await started();
    await app.close();
    final other = App(root: const CodeModule());

    expect(
      await callExtension(HotReloadExtension.reassembleMethod),
      isNotEmpty,
    );
    await expectLater(
      other.reassemble(),
      throwsA(isA<ApplicationStateError>()),
    );
  });

  test('close closes every open application', () async {
    final first = await started();
    final second = await started();

    final result = await callExtension(HotReloadExtension.closeMethod);

    expect(result, {'applications': 2});
    expect(first.isClosed && second.isClosed, isTrue);
  });
}
