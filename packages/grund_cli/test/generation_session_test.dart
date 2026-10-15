import 'dart:io';

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

void main() {
  test('the library is generated, then reported up to date', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);

    final first = await session.run();
    final generated = package.dir.read(ShopSources.output);
    final second = await session.run();

    expect(first.outcome, WriteOutcome.written);
    expect(first.output, ShopSources.output);
    expect(generated, startsWith(LibraryWriter.header));
    expect(generated, contains('grund.Module appModule()'));
    expect(second.outcome, WriteOutcome.unchanged);
    expect(package.dir.read(ShopSources.output), generated);
  });

  test('diagnostics keep the previous library', () async {
    final package = await TempPackage.create('shop', ShopSources.files);
    final session = _open(package);
    await session.run();
    final generated = package.dir.read(ShopSources.output);

    final report = await _change(
      session,
      package,
      _module,
      ShopSources.moduleWithoutClock,
    );

    expect(report.outcome, WriteOutcome.kept);
    expect(report.hasProblems, isTrue);
    expect(report.problemLines, [
      'lib/src/time_controller.dart:7:23: error: No provider for Clock in '
          'module "app" (resolving: TimeController). [missing_provider]',
    ]);
    expect(package.dir.read(ShopSources.output), generated);
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
  test('a package without annotations has no generated library', () async {
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

    expect(first.outcome, WriteOutcome.deleted);
    expect(package.dir.exists(ShopSources.output), isFalse);
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
      backward.dir.read(ShopSources.output),
      forward.dir.read(ShopSources.output),
    );
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
