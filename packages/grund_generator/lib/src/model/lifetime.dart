/// How long the instances of a binding live; the generated binding class
/// (`Singleton`, `Scoped`, `Transient`) follows from it.
enum Lifetime {
  /// One instance per application: `Singleton`.
  singleton,

  /// One instance per call: `Scoped` (`Scope.call` in annotations).
  scoped,

  /// A new instance on every resolution: `Transient`.
  transient,
}
