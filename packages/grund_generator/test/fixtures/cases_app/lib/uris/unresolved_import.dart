// A library whose import has a typo: the annotations it brings are unreadable.
// ignore_for_file: uri_does_not_exist, undefined_annotation
// The ignore is deliberate: the unresolved import is what the test needs.
import 'package:grund/annotationz.dart';
import 'package:grund/grund.dart' as grund;

/// Uses an annotation of the library that did not resolve.
@Module()
final class BrokenModule extends grund.Module {
  /// Creates the module.
  const BrokenModule();
}
