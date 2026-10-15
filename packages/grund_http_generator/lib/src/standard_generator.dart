import 'package:grund_generator/grund_generator.dart';

import 'construct/api_construct.dart';

/// The generator every driver runs unless it is given another one.
///
/// The command line and the build_runner builder both use it, so they write
/// the same bytes; composing the constructs in two places would let them
/// drift apart.
abstract final class StandardGenerator {
  /// The modules with their bindings, and the `@Api` classes with their
  /// routes.
  static const instance = GrundGenerator([ModuleConstruct(), ApiConstruct()]);
}
