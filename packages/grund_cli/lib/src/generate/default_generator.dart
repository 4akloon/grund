import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/grund_http_generator.dart';

/// The generator the command line runs unless it is given another one.
abstract final class DefaultGenerator {
  /// The modules with their bindings, and the `@Api` classes with their
  /// routes.
  static const instance = GrundGenerator([ModuleConstruct(), ApiConstruct()]);
}
