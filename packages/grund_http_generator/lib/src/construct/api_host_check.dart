import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;

import '../diagnostic/http_diagnostic_codes.dart';
import '../emit/http_references.dart';
import '../model/api_host.dart';
import '../model/api_names.dart';
import '../model/http_package_model.dart';

/// Checks that every library with `@Api` classes can host the generated
/// part: it includes the part and imports `package:grund_http` with the
/// prefix the generated code uses.
abstract final class ApiHostCheck {
  /// The problems of the hosts of [model].
  static Iterable<Diagnostic> check(HttpPackageModel model) => [
    for (final host in model.hosts) ...[
      if (!host.hasPartDirective && !host.declaresModule) _missingPart(host),
      if (!host.hasHttpImport) _missingImport(host),
    ],
  ];

  static Diagnostic _missingPart(ApiHost host) {
    final part = p.posix.basename(ApiNames.partPath(host.path));
    return Diagnostic(
      HttpDiagnosticCodes.missingPartDirective,
      host.location,
      '${host.path} declares @Api classes, whose routes are generated into '
      "$part, but does not include it. Add `part '$part';`.",
    );
  }

  static Diagnostic _missingImport(ApiHost host) => Diagnostic(
    HttpDiagnosticCodes.missingRequiredImport,
    host.location,
    '${host.path} declares @Api classes, whose generated routes name '
    '`${HttpReferences.importPrefix}.…` declarations, but does not import '
    'them with that prefix. Add `${HttpReferences.importDirective}`.',
  );
}
