import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:test/test.dart';

/// What the analyzer reports for a package that `init` wrote.
abstract final class DartDiagnostics {
  /// Errors and warnings of the Dart files of [root]'s `lib/`, `bin/` and
  /// `test/`; infos are dropped.
  static Future<List<String>> of(String root) async {
    final collection = AnalysisContextCollection(includedPaths: [root]);
    addTearDown(collection.dispose);
    final files = [
      for (final directory in ['lib', 'bin', 'test'])
        for (final entity in Directory(
          '$root/$directory',
        ).listSync(recursive: true))
          if (entity.path.endsWith('.dart')) entity.path,
    ];
    return [
      for (final file in files)
        if (await collection.contextFor(file).currentSession.getErrors(file)
            case final ErrorsResult result)
          for (final diagnostic in result.diagnostics)
            if (diagnostic.diagnosticCode.severity != DiagnosticSeverity.INFO)
              '$file: ${diagnostic.message}',
    ];
  }
}
