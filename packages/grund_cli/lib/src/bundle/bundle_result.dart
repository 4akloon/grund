/// How a [ClientBundler.build] ended.
sealed class BundleResult {
  const BundleResult();
}

/// The bundle was compiled and moved into place.
final class BundleBuilt extends BundleResult {
  /// Creates the result of a build that took [elapsed].
  const BundleBuilt(this.elapsed);

  /// How long the compilation took.
  final Duration elapsed;
}

/// The entry point does not exist: there was nothing to build.
final class BundleSkipped extends BundleResult {
  /// Creates the result.
  const BundleSkipped();
}

/// The compiler failed; the output directory was not touched.
final class BundleFailed extends BundleResult {
  /// Creates the result of a compilation that printed [output].
  const BundleFailed(this.output);

  /// What the compiler printed.
  final String output;
}
