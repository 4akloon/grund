/// Annotations for grund applications.
///
/// `grund_generator` reads them and writes ordinary code on the explicit
/// `package:grund` and `package:grund_http` API into
/// `lib/<package>.grund.dart`. The annotations have no runtime behavior and
/// this package has no dependencies.
///
/// `Module` shares its name with the explicit API; a library that needs both
/// imports `package:grund/grund.dart` with a prefix (`as grund`).
library;

export 'src/api.dart';
export 'src/bind.dart';
export 'src/injectable.dart';
export 'src/module.dart';
export 'src/named.dart';
export 'src/parameter_annotation.dart';
export 'src/provides.dart';
export 'src/route_annotation.dart';
export 'src/scope.dart';
export 'src/validator_annotation.dart';
