/// Annotations for dartnest applications.
///
/// `dartnest_generator` reads them and writes ordinary code on the explicit
/// `package:dartnest` API into `lib/<package>.dartnest.dart`. The
/// annotations have no runtime behavior and this package has no
/// dependencies.
///
/// `Module` and `Controller` share their names with the explicit API; a
/// library that needs both imports `package:dartnest/dartnest.dart` with
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
