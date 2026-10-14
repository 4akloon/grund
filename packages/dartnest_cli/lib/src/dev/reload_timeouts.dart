/// How long `dev` waits for a hung application or VM service before it
/// gives up on a step; tests pass short ones.
final class ReloadTimeouts {
  /// Creates the timeouts; the defaults are those `dev` runs with.
  const ReloadTimeouts({
    this.connect = const Duration(seconds: 5),
    this.reload = const Duration(seconds: 60),
    this.close = const Duration(seconds: 5),
    this.serviceUri = const Duration(seconds: 30),
  });

  /// Opening the connection to the VM service.
  final Duration connect;

  /// A whole hot reload: the VM's reload plus the reassemble.
  final Duration reload;

  /// Closing the dartnest applications and the connection.
  final Duration close;

  /// The child printing its VM service address after it started.
  final Duration serviceUri;
}
