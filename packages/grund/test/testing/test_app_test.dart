import 'package:grund/grund.dart';
import 'package:grund/testing.dart';
import 'package:test/test.dart';

import '../helpers/di_fixtures.dart';
import '../helpers/fake_runner.dart';
import '../helpers/module_fixtures.dart';

void main() {
  group('TestApp', () {
    test('builds the graph without starting any runner', () async {
      final log = <String>[];
      final app = await TestApp.start(
        root: AppModule(bindings: [runnerBinding(FakeRunner('a', log))]),
      );

      expect(log, ['prepare a']);
      await app.close();
    });

    test('resolves bindings of the root module', () async {
      final app = await TestApp.start(
        root: AppModule(
          bindings: [Singleton<Clock>((i) => Clock(), dependsOn: const [])],
        ),
      );

      expect(app<Clock>(), isA<Clock>());
      await app.close();
    });

    test('takes overrides', () async {
      final replacement = Clock();
      final app = await TestApp.start(
        root: AppModule(
          bindings: [Singleton<Clock>((i) => Clock(), dependsOn: const [])],
        ),
        overrides: [Singleton<Clock>((i) => replacement, dependsOn: const [])],
      );

      expect(app<Clock>(), same(replacement));
      await app.close();
    });

    test('reports a broken graph like a real start', () async {
      await expectLater(
        TestApp.start(
          root: AppModule(
            bindings: [
              Singleton<Repo>(
                (i) => Repo(i()),
                dependsOn: const [Key<Clock>()],
              ),
            ],
          ),
        ),
        throwsA(isA<MissingProviderError>()),
      );
    });
  });
}
