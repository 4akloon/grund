import 'dart:io';

import 'package:dartnest_cli/src/cli/report_printer.dart';
import 'package:dartnest_cli/src/generate/generation_report.dart';
import 'package:dartnest_cli/src/generate/write_outcome.dart';
import 'package:test/test.dart';

import 'helpers/cli_run.dart';
import 'helpers/shop_sources.dart';
import 'helpers/temp_package.dart';

String _print(WriteOutcome outcome) {
  final out = StringBuffer();
  ReportPrinter(out, StringBuffer()).report(
    GenerationReport(
      output: 'lib/shop.dartnest.dart',
      outcome: outcome,
      elapsed: const Duration(milliseconds: 7),
    ),
  );
  return '$out';
}

void main() {
  test('a deleted output is announced', () {
    expect(
      _print(WriteOutcome.deleted),
      'No annotations in lib/; deleted lib/shop.dartnest.dart.\n',
    );
  });

  test('a kept output is announced', () {
    expect(
      _print(WriteOutcome.kept),
      'lib/shop.dartnest.dart was not changed.\n',
    );
  });

  test('gen without --directory generates the current directory', () async {
    final package = await TempPackage.create('shop', ShopSources.files);

    final run = await IOOverrides.runZoned(
      () => CliRun.run(['gen']),
      getCurrentDirectory: () => Directory(package.dir.path),
    );

    expect(run.exitCode, 0);
    expect(package.dir.exists(ShopSources.output), isTrue);
  });
}
