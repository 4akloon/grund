/// HTTP annotations for grund applications.
///
/// `grund_http_generator` reads them and writes ordinary code on the
/// explicit `package:grund_http` API into `X_api.g.dart`. The annotations
/// have no runtime behavior.
///
/// A separate library because `Pattern` and `Cookie` share their names with
/// `dart:core` and `dart:io`: only a library that uses these annotations
/// imports it.
library;

export 'src/annotations/api.dart';
export 'src/annotations/parameter_annotation.dart';
export 'src/annotations/route_annotation.dart';
export 'src/annotations/validator_annotation.dart';
