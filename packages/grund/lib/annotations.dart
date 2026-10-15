/// Dependency-injection annotations for grund applications.
///
/// `grund_generator` reads them and writes ordinary code on the explicit
/// `package:grund` API into `X.g.dart`. The annotations have no
/// runtime behavior.
///
/// A separate library because `Module` shares its name with the base class
/// exported by `package:grund/grund.dart`: a library that needs both imports
/// that one with a prefix (`as grund`).
library;

export 'src/annotations/bind.dart';
export 'src/annotations/injectable.dart';
export 'src/annotations/module.dart';
export 'src/annotations/named.dart';
export 'src/annotations/provides.dart';
export 'src/annotations/scope.dart';
