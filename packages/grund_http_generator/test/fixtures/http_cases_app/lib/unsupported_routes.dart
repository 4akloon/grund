// Route annotations the generator cannot read.
//
// The unresolved identifier is the point of the fixture: the generator
// must report it, not default.
// ignore_for_file: undefined_identifier, const_with_non_constant_argument
import 'package:grund_annotations/grund_annotations.dart';

/// A route to mix in.
mixin RouteMixin {
  /// A mixed-in route.
  @Get('/mixed')
  String mixed() => '';
}

/// A base with a route.
base class Base {
  /// An inherited route.
  @Get('/inherited')
  String inherited() => '';
}

/// Inherits a route.
@Api('/a')
final class InheritingApi extends Base {}

/// Mixes in a route.
@Api('/b')
final class MixingApi with RouteMixin {}

/// Route with a path that is not a constant string.
@Api('/c')
final class PathApi {
  /// The route.
  @Get(missingPath)
  String route() => '';
}
