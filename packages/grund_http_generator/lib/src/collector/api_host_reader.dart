import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:path/path.dart' as p;

import '../emit/http_references.dart';
import '../model/api_host.dart';
import '../model/api_names.dart';

/// Reads what a library with `@Api` classes declares about the generated
/// part: its `part` directive and its imports.
abstract final class ApiHostReader {
  /// The host model of [library] at package-relative [path], whose first
  /// `@Api` class is at [firstApi].
  static ApiHost read(
    LibraryElement library,
    String path,
    SourceLocation firstApi,
  ) {
    final fragment = library.firstFragment;
    final partName = p.posix.basename(ApiNames.partPath(path));
    return ApiHost(
      path: path,
      location: firstApi,
      hasPartDirective: fragment.partIncludes.any(
        (include) => _uri(include.uri) == partName,
      ),
      hasHttpImport: fragment.libraryImports.any(
        (import) =>
            import.prefix?.element.name == HttpReferences.importPrefix &&
            _uri(import.uri) == HttpReferences.importUri,
      ),
    );
  }

  static String? _uri(DirectiveUri uri) =>
      uri is DirectiveUriWithRelativeUriString ? uri.relativeUriString : null;
}
