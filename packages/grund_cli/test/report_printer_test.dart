import 'dart:io';

import 'package:grund_cli/src/cli/report_printer.dart';
import 'package:grund_cli/src/generate/generation_report.dart';
import 'package:grund_cli/src/generate/synced_files.dart';
import 'package:grund_cli/src/generate/write_outcome.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

String _print(WriteOutcome outcome, [SyncedFiles? synced]) {
  final out = StringBuffer();
  ReportPrinter(out, StringBuffer()).report(
    GenerationReport(
      outcome: outcome,
      elapsed: const Duration(milliseconds: 7),
      synced: synced,
    ),
  );
  return '$out';
}

void main() {
  test('written files are counted, stale ones too', () {
    expect(
      _print(
        WriteOutcome.written,
        const SyncedFiles(
          written: ['lib/a_module.g.dart'],
          deleted: ['lib/b_api.g.dart', 'lib/c_api.g.dart'],
          total: 3,
        ),
      ),
      'Generated 1 file, deleted 2 stale files in 7 ms.\n',
    );
  });

  test('deleting the last generated files is announced', () {
    expect(
      _print(
        WriteOutcome.written,
        const SyncedFiles(written: [], deleted: ['lib/b_api.g.dart'], total: 0),
      ),
      'No annotations in lib/; deleted 1 stale file.\n',
    );
  });

  test('unchanged files are announced', () {
    expect(
      _print(
        WriteOutcome.unchanged,
        const SyncedFiles(written: [], deleted: [], total: 1),
      ),
      'Generated files are up to date (1 file, 7 ms).\n',
    );
  });

  test('a kept output is announced', () {
    expect(_print(WriteOutcome.kept), 'No generated file was changed.\n');
  });

  test('gen without --directory generates the current directory', () async {
    final package = await TempPackage.create('shop', ShopSources.files);

    final run = await IOOverrides.runZoned(
      () => CliRun.run(['gen']),
      getCurrentDirectory: () => Directory(package.dir.path),
    );

    expect(run.exitCode, 0);
    expect(package.dir.exists(ShopSources.moduleOutput), isTrue);
  });
}
