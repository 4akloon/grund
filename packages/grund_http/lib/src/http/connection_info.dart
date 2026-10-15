/// Network details of the connection a request arrived on, as reported by
/// the `HttpAdapter`.
final class ConnectionInfo {
  /// Creates connection details.
  const ConnectionInfo({required this.remoteAddress, required this.remotePort});

  /// Address of the client (an IP address in text form).
  final String remoteAddress;

  /// Port of the client.
  final int remotePort;
}
