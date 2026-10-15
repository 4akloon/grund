/// The outcome of one hot reload of the application process.
sealed class ReloadResult {
  const ReloadResult();
}

/// The VM took the new code; the applications were then reassembled.
final class Reloaded extends ReloadResult {
  /// Creates the result.
  const Reloaded({
    required this.libraries,
    required this.elapsed,
    this.changedRoutes,
    this.reassembleError,
  });

  /// How many libraries the VM loaded.
  final int libraries;

  /// How long the reload and the reassemble took.
  final Duration elapsed;

  /// How many routes were added or removed; `null` when no grund
  /// application was reassembled.
  final int? changedRoutes;

  /// Why the reassemble failed (the previous application state keeps
  /// serving); `null` when it succeeded or did not run.
  final String? reassembleError;
}

/// The new code does not compile; the process keeps running the previous
/// code.
final class ReloadFailed extends ReloadResult {
  /// Creates the result.
  const ReloadFailed(this.message);

  /// The compiler's errors, or why the VM service could not reload.
  final String message;
}

/// The VM cannot apply the change to the running process (a limitation of
/// hot reload, for example changed type parameters); it needs a restart.
final class ReloadRejected extends ReloadResult {
  /// Creates the result.
  const ReloadRejected(this.reason);

  /// The VM's reason.
  final String reason;
}
