// Scopes that need evaluating, and annotations the generator cannot read.
//
// The unresolved identifiers are the point of the fixture: the generator
// must report them, not default.
// ignore_for_file: undefined_identifier, const_with_non_constant_argument, const_eval_method_invocation
import 'package:grund/grund.dart' as grund;
import 'package:grund_annotations/grund_annotations.dart';

import 'modules/basic.dart';

/// An alias of a scope.
const callScope = Scope.call;

/// Scope through an alias.
@Injectable(scope: callScope)
final class AliasedScope {}

/// Scope that does not resolve.
@Injectable(scope: Undefined.scope)
final class UnresolvedScope {}

/// A `Bind` implementation with its own name.
@Injectable()
@Named('custom')
final class NamedClock implements Clock {
  @override
  DateTime now() => DateTime(2000);
}

/// Provides with an alias and with an unresolved scope.
@Module(providers: [AliasedScope, Bind<Clock, NamedClock>()])
final class ScopedModule extends grund.Module {
  /// Creates the module.
  const ScopedModule();

  /// Through an alias.
  @Provides(scope: callScope)
  static Tx aliased() => Tx();

  /// Unresolved.
  @Provides(scope: Undefined.scope)
  static Repo unresolved() => throw UnimplementedError();

  /// A future of a future.
  @Provides()
  static Future<Future<Tx>> nested() async => Future<Tx>.value(Tx());

  /// A nullable future.
  @Provides()
  static Future<Tx>? nullable() => null;
}

/// Routes and providers to inherit.
mixin RouteMixin {
  /// A mixed-in route.
  @Get('/mixed')
  String mixed() => '';
}

/// A base with a route and a provider.
base class Base {
  /// An inherited route.
  @Get('/inherited')
  String inherited() => '';

  /// An inherited provider.
  @Provides()
  static Tx tx() => Tx();
}

/// Inherits a route.
@Api('/a')
final class InheritingApi extends Base {}

/// Mixes in a route.
@Api('/b')
final class MixingApi with RouteMixin {}

/// Inherits a provider.
@Module()
final class InheritingModule extends Base {}

/// Annotation on a mixin.
@Injectable()
mixin AnnotatedMixin {}

/// Annotation on an enum.
@Injectable()
enum AnnotatedEnum { one }

/// Route with a path that is not a constant string.
@Api('/c')
final class PathApi {
  /// The route.
  @Get(missingPath)
  String route() => '';
}

/// An annotation whose constant does not evaluate at all.
@Injectable(scope: pick())
final class BrokenAnnotation {}

/// Not a constant.
Scope pick() => Scope.call;
