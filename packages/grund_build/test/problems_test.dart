import 'package:grund_build/grund_build.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/cli_generation.dart';
import 'helpers/shop_sources.dart';
import 'helpers/test_constructs.dart';

Future<BuildRun> _build(Map<String, String> files) =>
    BuildRun.run(GrundBuilder(), ShopSources.package, files);

void main() {
  final withBroken = {
    ...ShopSources.files,
    'lib/src/broken.dart': ShopSources.broken,
  };

  test('syntax errors are reported as the CLI reports them', () async {
    final build = await _build(withBroken);
    final cli = await CliGeneration.run(ShopSources.package, withBroken);

    expect(cli.report.syntaxProblems, hasLength(2));
    expect(build.errors, cli.report.problemLines);
  });

  test('a syntax error fails the build', () async {
    final build = await _build(withBroken);

    expect(build.succeeded, isFalse);
  });

  test('a library that reaches a broken one writes nothing', () async {
    final build = await _build({
      ...withBroken,
      'lib/src/app_module.dart': ShopSources.module.replaceFirst(
        "import 'clock.dart';",
        "import 'broken.dart';\nimport 'clock.dart';",
      ),
    });

    expect(build.outputs.keys, [ShopSources.apiOutput]);
  });

  test('a syntax error in a part file is reported at the part', () async {
    final files = {
      'lib/src/user.dart': "part 'user_part.dart';\n",
      'lib/src/user_part.dart': "part of 'user.dart';\n\nvoid f( {}\n",
    };

    final build = await _build(files);
    final cli = await CliGeneration.run(ShopSources.package, files);

    expect(build.errors, everyElement(startsWith('lib/src/user_part.dart:')));
    expect(build.errors, cli.report.problemLines);
  });

  group('a problem in a module that another module imports', () {
    final files = {
      ...ShopSources.files,
      'lib/src/inner.dart': ShopSources.inner,
      'lib/src/outer.dart': ShopSources.outer,
    };

    test('is reported once, by the step of its own library', () async {
      final build = await _build(files);
      final cli = await CliGeneration.run(ShopSources.package, files);

      expect(cli.report.diagnostics, hasLength(1));
      expect(build.errors, hasLength(2));
      // The CLI's message may add a hint naming modules the step does not
      // reach (here AppModule), so only the location and code must agree.
      expect(build.errors.first, startsWith('lib/src/inner.dart:9:19: error'));
      expect(build.errors.first, endsWith('[missing_provider]'));
      expect(
        build.errors.last,
        'lib/src/outer.dart was not generated: lib/src/inner.dart has '
        'problems',
      );
      expect(
        cli.report.problemLines.single,
        startsWith('lib/src/inner.dart:9:19'),
      );
    });

    test('writes no file of the importing library', () async {
      final build = await _build(files);

      expect(
        build.outputs.keys,
        isNot(contains('lib/src/outer_module.g.dart')),
      );
    });

    test('fixed, writes the same files as the CLI', () async {
      final fixed = {
        ...files,
        'lib/src/inner.dart': ShopSources.inner.replaceFirst(
          'providers: [NeedsClock]',
          'providers: [Clock, NeedsClock]',
        ),
      };

      final build = await _build(fixed);
      final cli = await CliGeneration.run(ShopSources.package, fixed);

      expect(build.succeeded, isTrue);
      expect(build.outputs, cli.files);
    });
  });
  test(
    'a reached broken library that is no input still fails the step',
    () async {
      final build = await BuildRun.run(
        GrundBuilder(),
        ShopSources.package,
        {
          ...withBroken,
          'lib/src/app_module.dart': ShopSources.module.replaceFirst(
            "import 'clock.dart';",
            "import 'broken.dart';\nimport 'clock.dart';",
          ),
        },
        inputs: {'lib/src/app_module.dart'},
      );

      expect(build.errors, [
        'lib/src/app_module.dart was not generated: lib/src/broken.dart has '
            'problems',
      ]);
      expect(build.outputs, isEmpty);
    },
  );

  test(
    'a problem only the wider reach produces is named by the step',
    () async {
      final build = await BuildRun.run(
        GrundBuilder(
          generator: GrundGenerator([
            ...StandardGenerator.instance.constructs,
            const TwoModulesConstruct('lib/src/clock.dart'),
          ]),
        ),
        ShopSources.package,
        {
          'lib/src/clock.dart': ShopSources.clock,
          'lib/src/only_module.dart': ShopSources.onlyModule,
          'lib/src/second.dart': ShopSources.second,
          'lib/src/both_modules.dart': ShopSources.bothModules,
        },
        inputs: {'lib/src/both_modules.dart'},
      );

      expect(build.errors, [
        'lib/src/both_modules.dart was not generated: lib/src/clock.dart has '
            'problems',
      ]);
    },
  );

  test('a file no library owns fails the step and writes nothing', () async {
    final build = await BuildRun.run(
      GrundBuilder(
        generator: GrundGenerator([
          ...StandardGenerator.instance.constructs,
          const FileConstruct(),
        ]),
      ),
      ShopSources.package,
      ShopSources.files,
    );

    expect(build.errors, hasLength(3));
    expect(
      build.errors,
      everyElement(startsWith('grund_build cannot write openapi.json:')),
    );
    expect(build.outputs, isEmpty);
  });
}
