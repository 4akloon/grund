import 'dart:io';

import 'package:grund_cli/src/cli/cli_failure.dart';
import 'package:grund_cli/src/generate/generation_report.dart';
import 'package:grund_cli/src/generate/generation_session.dart';
import 'package:grund_cli/src/generate/write_outcome.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

const _module = 'lib/src/app_module.dart';

GenerationSession _open(TempPackage package) {
  final session = GenerationSession(package.root);
  addTearDown(session.close);
  return session;
}

/// Rewrites [path] of [package] and runs [session] with that change.
Future<GenerationReport> _change(
  GenerationSession session,
  TempPackage package,
  String path,
  String content,
) => session.run(changed: [package.dir.write(path, content)]);

Map<String, String> _read(TempPackage package, List<String> paths) => {
  for (final path in paths) path: package.dir.read(path),
};

void main() {
  test('the file set is generated, then reported up to date', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);

    final first = await session.run();
    final generated = _read(package, ShopSources.outputs);
    final second = await session.run();

    expect(first.outcome, WriteOutcome.written);
    expect(first.synced?.written, ShopSources.outputs);
    expect(generated.values, everyElement(startsWith(LibraryWriter.header)));
    expect(
      generated[ShopSources.moduleOutput],
      contains('mixin \$AppModule on grund.Module'),
    );
    expect(
      generated[ShopSources.apiOutput],
      contains('final class TimeApiRoutes extends http.HttpApi'),
    );
    expect(second.outcome, WriteOutcome.unchanged);
    expect(second.synced?.total, 2);
    expect(_read(package, ShopSources.outputs), generated);
  });

  test('diagnostics keep the previous files', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();
    final generated = _read(package, ShopSources.outputs);

    final report = await _change(
      session,
      package,
      _module,
      ShopSources.moduleWithoutClock,
    );

    expect(report.outcome, WriteOutcome.kept);
    expect(report.hasProblems, isTrue);
    expect(report.problemLines, hasLength(1));
    expect(
      report.problemLines.single,
      allOf(
        startsWith('lib/src/time_api.dart:'),
        contains('Clock'),
        endsWith('[missing_provider]'),
      ),
    );
    expect(report.synced, isNull);
    expect(_read(package, ShopSources.outputs), generated);
  });

  // Review Focus 3: a syntax error, e.g. a file saved half-way.
  test('syntax errors stop generation until they are fixed', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();

    final broken = await _change(session, package, _module, 'class {');
    final fixed = await _change(session, package, _module, ShopSources.module);

    expect(broken.outcome, WriteOutcome.kept);
    expect(broken.diagnostics, isEmpty);
    expect(broken.problemLines, everyElement(startsWith('$_module:1:')));
    expect(fixed.outcome, WriteOutcome.unchanged);
    expect(fixed.hasProblems, isFalse);
  });

  // Review Focus 4: the last annotation is removed.
  test('a package without annotations has no generated files', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();

    final changed = [
      for (final path in ShopSources.files.keys) package.dir.resolve(path),
    ];
    for (final path in changed) {
      File(path).deleteSync();
    }
    final first = await session.run(changed: changed);
    final second = await session.run();

    expect(first.outcome, WriteOutcome.written);
    expect(first.synced?.deleted, ShopSources.outputs);
    for (final output in ShopSources.outputs) {
      expect(package.dir.exists(output), isFalse);
    }
    expect(second.outcome, WriteOutcome.none);
  });

  // Review Focus 7: the file system lists files in any order.
  test('the output does not depend on the order files were created', () async {
    final forward = await TempPackage.create('shop', ShopSources.files);
    final backward = await TempPackage.create('shop', {
      for (final entry in ShopSources.files.entries.toList().reversed)
        entry.key: entry.value,
    });

    await _open(forward).run();
    await _open(backward).run();

    expect(
      _read(backward, ShopSources.outputs),
      _read(forward, ShopSources.outputs),
    );
  });

  test(
    'a generated file that no longer belongs to the set is deleted',
    () async {
      final package = await TempPackage.create('shop', ShopSources.files);
      final session = _open(package);
      await session.run();

      final report = await _change(
        session,
        package,
        'lib/src/time_api.dart',
        "import 'package:grund/annotations.dart';\n\n"
            '@Injectable()\nfinal class TimeApi {}\n',
      );

      expect(report.hasProblems, isFalse, reason: '${report.problemLines}');
      expect(report.synced?.deleted, [ShopSources.apiOutput]);
      expect(package.dir.exists(ShopSources.apiOutput), isFalse);
    },
  );

  test('stale files stay while the sources have problems', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();

    final report = await _change(
      session,
      package,
      'lib/src/time_api.dart',
      'class {',
    );

    expect(report.hasProblems, isTrue);
    expect(report.synced, isNull);
    for (final output in ShopSources.outputs) {
      expect(package.dir.exists(output), isTrue);
    }
  });

  test('a generated file is never read back as a source', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();
    final broken = package.dir.write(
      ShopSources.moduleOutput,
      '${LibraryWriter.header}\nclass {',
    );

    final report = await session.run(changed: [broken]);

    expect(report.hasProblems, isFalse);
    expect(report.synced?.written, [ShopSources.moduleOutput]);
    expect(
      package.dir.read(ShopSources.moduleOutput),
      contains('mixin \$AppModule'),
    );
  });

  test('a hand-written file at an output path stops the run', () async {
    final package = await TempPackage.create('shop', {
      ...ShopSources.files,
      ShopSources.apiOutput: '// mine\n',
    });
    final session = _open(package);

    await expectLater(session.run, throwsA(isA<CliFailure>()));

    expect(package.dir.read(ShopSources.apiOutput), '// mine\n');
    expect(package.dir.exists(ShopSources.moduleOutput), isFalse);
  });

  test('paths outside lib/ are ignored', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();

    final report = await session.run(
      changed: [package.dir.write('test/other_test.dart', 'void main() {}')],
    );

    expect(report.outcome, WriteOutcome.unchanged);
  });
}
