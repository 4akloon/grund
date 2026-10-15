import 'package:grund_cli/grund_cli.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

Future<CliRun> _gen(TempPackage package) =>
    CliRun.run(['gen', '--directory', package.dir.path]);

void main() {
  test('a mistyped import keeps the outputs and exits with 1', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    await _gen(package);
    final before = {
      for (final output in ShopSources.outputs)
        output: package.dir.read(output),
    };
    package.dir.write(
      'lib/src/clock.dart',
      ShopSources.clock.replaceFirst('annotations.dart', 'annotationz.dart'),
    );

    final run = await _gen(package);

    expect(run.exitCode, CliExitCode.problems.code);
    expect(run.err, startsWith('lib/src/clock.dart:1:1: '));
    expect(run.err, contains('package:grund/annotationz.dart'));
    expect(run.err, contains('[unresolved_uri]'));
    expect(run.err, contains('no generated file was changed'));
    expect(run.out, isNot(contains('Deleted')));
    for (final output in ShopSources.outputs) {
      expect(package.dir.read(output), before[output]);
    }
  });

  test(
    'a mistyped import in the only annotated file deletes nothing',
    () async {
      final package = await TempPackage.create('shop', {
        'lib/src/clock.dart': ShopSources.clock.replaceFirst(
          'annotations.dart',
          'annotationz.dart',
        ),
        'lib/src/app_module.g.dart': '${LibraryWriter.header}\n',
      });

      final run = await _gen(package);

      expect(run.exitCode, CliExitCode.problems.code);
      expect(package.dir.exists('lib/src/app_module.g.dart'), isTrue);
    },
  );
}
