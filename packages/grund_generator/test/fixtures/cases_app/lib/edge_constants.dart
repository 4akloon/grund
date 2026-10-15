// Edge-case constants for ConstantReader tests: each class below carries one
// [Probe] whose single argument is read by class name.
import 'constants.dart' show Marker;

/// Metadata that wraps any constant.
final class Probe extends Marker {
  /// Creates the metadata.
  const Probe(this.value);

  /// The wrapped constant.
  final Object? value;
}

/// A class with a private constructor.
final class Locked {
  const Locked._();
}

const _locked = Locked._();

/// A class with a public static constant.
final class Limits {
  /// The maximum.
  static const max = 5;
}

final class _Private {
  static const value = 7;
}

/// A function to tear off.
void tearOff() {}

/// Null.
@Probe(null)
class NullCase {}

/// A bool.
@Probe(true)
class BoolCase {}

/// A double.
@Probe(1.5)
class DoubleCase {}

/// A non-finite double.
@Probe(1 / 0)
class InfiniteCase {}

/// A private constructor.
@Probe(_locked)
class LockedCase {}

/// A function, which is not a constructor call.
@Probe(tearOff)
class FunctionCase {}

/// A static constant of a public class.
@Probe(Limits.max)
class StaticCase {}

/// A static constant of a private class.
@Probe(_Private.value)
class PrivateOwnerCase {}
