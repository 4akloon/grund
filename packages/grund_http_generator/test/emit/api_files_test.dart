import 'dart:io';

import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

/// The generated part that is committed in the fixture, so the root
/// `dart analyze` compiles it against `grund_http`.
const _committed = 'test/fixtures/http_cases_app/lib/apis/tasks_api.g.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('http_cases_app'));

  Future<GenerationResult> generate(List<String> paths) async =>
      const GrundGenerator(
        FixturePackage.constructs,
      ).generate(await fixture.collect(paths));

  test('a library with an @Api and no @Module still gets its part', () async {
    final result = await generate(['lib/apis/tasks.dart']);

    expect(result.diagnostics, isEmpty);
    expect(result.files.keys, ['lib/apis/tasks_api.g.dart']);
  });

  test('the module file binds the routes right after the api', () async {
    final result = await generate([
      'lib/modules/with_api.dart',
      'lib/apis/tasks.dart',
    ]);
    final module = result.files['lib/modules/with_api_module.g.dart'] ?? '';

    expect(module, contains('grund.Singleton<i1.TasksApiRoutes>('));
    expect(module, contains('(i) => i1.TasksApiRoutes(i, i<i1.TasksApi>())'));
    expect(
      module.indexOf('Singleton<i1.TasksApi>('),
      lessThan(module.indexOf('Singleton<i1.TasksApiRoutes>(')),
    );
    expect(module, isNot(contains('tasks_api.g.dart')));
  });

  test('two runs write the same bytes', () async {
    final paths = ['lib/modules/with_api.dart', 'lib/apis/tasks.dart'];

    final first = await generate(paths);
    final second = await generate(paths);

    expect(second.files, first.files);
  });

  test('the committed part is what the generator writes', () async {
    final result = await generate(['lib/apis/tasks.dart']);
    final generated = result.files['lib/apis/tasks_api.g.dart'] ?? '';

    if (Platform.environment['GRUND_UPDATE_GOLDENS'] == '1') {
      File(_committed).writeAsStringSync(generated);
    }
    expect(File(_committed).readAsStringSync(), generated);
  });
}
