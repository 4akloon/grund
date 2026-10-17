import 'package:grund/src/config/environment_module.dart';
import 'package:grund/src/config/environment.dart';
import 'package:grund/src/di/binding.dart';
import 'package:grund/src/di/container.dart';
import 'package:grund/src/di/key.dart';
import 'package:grund/src/di/module_graph.dart';
import 'package:grund/src/errors/environment_errors.dart';
import 'package:grund/src/errors/resolution_errors.dart';
import 'package:test/test.dart';

import '../helpers/module_fixtures.dart';

Future<Container> start(
  StubModule root, {
  List<Binding<Object>> overrides = const [],
}) => Container.create(ModuleGraph.build(root, overrides: overrides));

void main() {
  group('EnvironmentModule', () {
    test('is global and exports Environment', () {
      const module = EnvironmentModule();

      expect(module.global, isTrue);
      expect(module.exports, [const Key<Environment>()]);
    });

    test('is visible to a module that does not import it', () async {
      final container = await start(
        AppModule(
          imports: const [EnvironmentModule()],
          bindings: [
            Singleton<String>(
              (i) => i<Environment>().string('PATH', fallback: ''),
              dependsOn: const [Key<Environment>()],
            ),
          ],
        ),
      );

      expect(container.root<Environment>(), isA<Environment>());
    });

    test('lets an override replace the process environment', () async {
      final container = await start(
        const AppModule(imports: [EnvironmentModule()]),
        overrides: [
          Singleton<Environment>(
            (_) => const Environment({'PORT': '0'}),
            dependsOn: const [],
          ),
        ],
      );

      expect(container.root<Environment>().integer('PORT'), 0);
    });

    test('a failing read passes through the container unwrapped', () async {
      final root = AppModule(
        imports: const [EnvironmentModule()],
        bindings: [
          Singleton<int>(
            (i) => i<Environment>().integer('SECRET'),
            dependsOn: const [Key<Environment>()],
          ),
        ],
      );

      await expectLater(
        start(
          root,
          overrides: [
            Singleton<Environment>(
              (_) => const Environment({'SECRET': 'hunter2'}),
              dependsOn: const [],
            ),
          ],
        ),
        throwsA(
          isA<InvalidVariableError>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains('hunter2')),
          ),
        ),
      );
    });

    test('a wrapper around the error does not show the value', () {
      final wrapper = ProviderCreationError(
        key: const Key<int>(),
        module: 'AppModule',
        chain: const [],
        error: const InvalidVariableError(
          name: 'SECRET',
          expected: 'an integer',
        ),
        stackTrace: StackTrace.current,
      );

      expect(wrapper.message, contains('SECRET'));
      expect(wrapper.message, isNot(contains('hunter2')));
      expect(wrapper.toString(), isNot(contains('hunter2')));
    });
  });
}
