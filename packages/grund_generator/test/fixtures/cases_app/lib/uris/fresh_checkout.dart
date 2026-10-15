// A host library that parts and imports its own output, missing on a fresh
// checkout.
// ignore_for_file: uri_has_not_been_generated
// The ignore is deliberate: the file does not exist before the first run.
import 'package:grund/annotations.dart';
import 'package:grund/grund.dart' as grund;

import 'fresh_checkout.g.dart';

part 'fresh_checkout_part.g.dart';

/// A module of a freshly checked out package.
@Module()
final class FreshModule extends grund.Module {
  /// Creates the module.
  const FreshModule();
}
