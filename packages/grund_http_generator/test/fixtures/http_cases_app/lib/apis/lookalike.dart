// A route annotation named `Get`, declared in this package.
import 'package:grund_http/annotations.dart' hide Get;

/// Not the annotation of `package:grund_http`.
final class Get {
  /// Creates it.
  const Get(this.path);

  /// Ignored.
  final String path;
}

/// An API whose only method carries the look-alike.
@Api('/lookalike')
final class LookalikeApi {
  /// Is not a route.
  @Get('/')
  String ping() => 'pong';
}
