/// Annotations for grund applications.
///
/// `grund_generator` reads them and writes ordinary code on the explicit
/// `package:grund` API into `lib/<package>.grund.dart`. The
/// annotations have no runtime behavior and this package has no
/// dependencies.
///
/// `Module` and `Controller` share their names with the explicit API; a
/// library that needs both imports `package:grund/grund.dart` with
/// `hide Controller, Module`.
library;

export 'src/argument_annotation.dart';
export 'src/bind.dart';
export 'src/controller.dart';
export 'src/inject.dart';
export 'src/injectable.dart';
export 'src/module.dart';
export 'src/route_annotation.dart';
export 'src/route_metadata.dart';
export 'src/use_components.dart';
export 'src/value.dart';
