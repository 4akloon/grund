import 'package:grund_generator/grund_generator.dart';

/// Where the HTTP generator finds annotations: the HTTP annotations of
/// `package:grund_http` and the core ones (`@Named` on a parameter).
abstract final class HttpAnnotations {
  /// URI prefix of the HTTP annotation classes of `package:grund_http`.
  static const library = 'package:grund_http/src/annotations/';

  /// The reader of the HTTP and the core annotations.
  static const reader = Annotations({Annotations.coreLibrary, library});
}
