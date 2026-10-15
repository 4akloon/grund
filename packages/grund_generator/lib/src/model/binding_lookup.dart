import '../diagnostic/source_location.dart';
import 'binding_key.dart';

/// A key a bound instance looks up each time it is used rather than when it
/// is created: it must be visible in the module, but it is no edge of the
/// dependency graph (no cycle, no captive dependency).
final class BindingLookup {
  /// Creates the lookup of [key], reported at [location] when it is missing.
  const BindingLookup(this.key, this.location);

  /// What is looked up.
  final BindingKey key;

  /// The declaration that makes the lookup.
  final SourceLocation location;
}
