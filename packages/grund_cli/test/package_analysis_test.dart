import 'dart:io';

import 'package:grund_cli/src/cli/cli_exit_code.dart';
import 'package:grund_cli/src/cli/cli_failure.dart';
import 'package:grund_cli/src/generate/package_analysis.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

PackageAnalysis _open(TempPackage package) {
  final analysis = PackageAnalysis(package.root);
  addTearDown(analysis.dispose);
  return analysis;
}

void main() {
  test('a lib/ that disappears is a no-input failure naming it', () async {
    final package = await TempPackage.create('shop', {'lib/a.dart': ''});
    final analysis = _open(package);
    Directory(package.dir.resolve('lib')).deleteSync(recursive: true);

    expect(
      analysis.sourceFiles,
      throwsA(
        isA<CliFailure>()
            .having((f) => f.exitCode, 'exitCode', CliExitCode.noInput)
            .having((f) => f.message, 'message', contains('lib')),
      ),
    );
  });

  test(
    'source files are the Dart files of lib/ except generated ones',
    () async {
      final package = await TempPackage.create('shop', {
        'lib/b.dart': '',
        'lib/a/z.dart': '',
        'lib/shop.grund.dart': '',
        'lib/notes.txt': '',
        'bin/main.dart': '',
      });
      final analysis = _open(package);

      expect(analysis.sourceFiles(), [
        package.dir.resolve('lib/a/z.dart'),
        package.dir.resolve('lib/b.dart'),
      ]);
    },
  );

  test('libraries are resolved and part files are skipped', () async {
    final package = await TempPackage.create('shop', {
      ...ShopSources.files,
      'lib/src/money.dart': "part 'money_part.dart';\n",
      'lib/src/money_part.dart': "part of 'money.dart';\nclass Cents {}\n",
    });
    final analysis = _open(package);

    final libraries = await analysis.libraries(analysis.sourceFiles());

    expect(
      [for (final l in libraries) '${l.uri}'],
      [
        'package:shop/src/app_module.dart',
        'package:shop/src/clock.dart',
        'package:shop/src/money.dart',
        'package:shop/src/time_controller.dart',
      ],
    );
  });

  test('syntax errors are reported with a package-relative location', () async {
    final package = await TempPackage.create('shop', {
      'lib/src/broken.dart': 'class Broken {\n  int x = ;\n}\n',
      'lib/src/fine.dart': "import 'package:shop/shop.grund.dart';\n",
    });
    final analysis = _open(package);

    final problems = analysis.syntaxProblems(analysis.sourceFiles());

    expect(problems, hasLength(1));
    expect(
      problems.single.location,
      const SourceLocation('lib/src/broken.dart', 2, 11),
    );
    expect(
      '${problems.single}',
      matches(
        RegExp(r'^lib/src/broken\.dart:2:11: error: .+ \[syntax_error\]$'),
      ),
    );
  });

  test(
    'a change is seen after it is reported, without a new analysis',
    () async {
      final package = await TempPackage.create('shop', ShopSources.files);
      final analysis = _open(package);
      final file = package.dir.resolve('lib/src/clock.dart');
      await analysis.libraries(analysis.sourceFiles());

      File(file).writeAsStringSync('final class Watch {}\n');
      await analysis.changed([file]);
      final libraries = await analysis.libraries([file]);

      expect([for (final c in libraries.single.classes) c.name], ['Watch']);
    },
  );
}
