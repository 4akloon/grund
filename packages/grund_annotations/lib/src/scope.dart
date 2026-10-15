/// How long the instances of a binding live.
///
/// `Scope.call` becomes `Scoped` in the generated bindings: one instance per
/// call (an HTTP request, a job run).
enum Scope {
  /// One instance per application, created at startup.
  singleton,

  /// One instance per call.
  call,

  /// A new instance on every resolution.
  transient,
}
