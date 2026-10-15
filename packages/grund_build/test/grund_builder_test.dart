import 'package:grund_build/grund_build.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/shop_sources.dart';

Future<BuildRun> _build(Map<String, String> files) =>
    BuildRun.run(GrundBuilder(), ShopSources.package, files);

void main() {
  test('a module library gets its module file and nothing else', () async {
    final build = await _build({
      'lib/src/clock.dart': ShopSources.clock,
      'lib/src/only_module.dart': ShopSources.onlyModule,
    });

    expect(build.succeeded, isTrue);
    expect(build.outputs.keys, ['lib/src/only_module_module.g.dart']);
  });

  test('an API library gets its part and no module file', () async {
    final build = await _build({
      'lib/src/clock.dart': ShopSources.clock,
      'lib/src/time_api.dart': ShopSources.api,
    });

    expect(build.succeeded, isTrue);
    expect(build.outputs.keys, [ShopSources.apiOutput]);
  });

  test('a library with a module and an API gets both files', () async {
    final build = await _build({'lib/src/both.dart': ShopSources.both});

    expect(build.succeeded, isTrue);
    expect(build.outputs.keys, [
      'lib/src/both_api.g.dart',
      'lib/src/both_module.g.dart',
    ]);
  });

  test('every library writes only its own files', () async {
    final build = await _build(ShopSources.files);

    expect(build.succeeded, isTrue);
    expect(build.outputs.keys, [
      ShopSources.moduleOutput,
      ShopSources.apiOutput,
    ]);
  });

  test('a package without annotations gets no file', () async {
    final build = await _build({
      'lib/src/plain.dart': 'final class Plain {}\n',
    });

    expect(build.succeeded, isTrue);
    expect(build.outputs, isEmpty);
  });

  test('generated files in lib/ are not inputs', () async {
    final first = await _build(ShopSources.files);
    final again = await _build({
      ...ShopSources.files,
      ...first.outputs,
      // A stale output that no longer parses must not fail the build.
      'lib/src/old_api.g.dart': '${LibraryWriter.header}\nthis is not Dart\n',
    });

    expect(again.succeeded, isTrue);
    expect(again.outputs, first.outputs);
  });

  test('a part file is not an input', () async {
    final build = await _build({
      'lib/src/clock.dart': ShopSources.clock,
      'lib/src/user.dart': "part 'user_part.dart';\n",
      'lib/src/user_part.dart': "part of 'user.dart';\n\nfinal class P {}\n",
    });

    expect(build.succeeded, isTrue);
    expect(build.outputs, isEmpty);
  });

  test('a library outside lib/ is not an input', () async {
    final build = await _build({
      'lib/src/clock.dart': ShopSources.clock,
      'test/helper.dart': ShopSources.onlyModule,
    });

    expect(build.outputs, isEmpty);
  });
}
