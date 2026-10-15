import 'package:grund_build/grund_build.dart';
import 'package:test/test.dart';

import 'helpers/build_run.dart';
import 'helpers/cli_generation.dart';
import 'helpers/shop_sources.dart';

void main() {
  final mistyped = {
    ...ShopSources.files,
    'lib/src/clock.dart': ShopSources.clock.replaceFirst(
      'annotations.dart',
      'annotationz.dart',
    ),
  };

  test('a mistyped import fails the step of its library', () async {
    final build = await BuildRun.run(
      GrundBuilder(),
      ShopSources.package,
      mistyped,
    );

    expect(build.succeeded, isFalse);
    expect(
      build.errors,
      contains(
        allOf(
          startsWith('lib/src/clock.dart:1:1'),
          contains('[unresolved_uri]'),
        ),
      ),
    );
  });

  test('the build and the CLI report the same unresolved import', () async {
    final build = await BuildRun.run(
      GrundBuilder(),
      ShopSources.package,
      mistyped,
    );
    final cli = await CliGeneration.run(ShopSources.package, mistyped);

    final unresolved = [
      for (final line in cli.report.problemLines)
        if (line.contains('[unresolved_uri]')) line,
    ];
    expect(unresolved, hasLength(1));
    expect(build.errors, containsAll(unresolved));
  });
}
