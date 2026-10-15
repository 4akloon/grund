/// How the HTTP server listens and what it accepts.
///
/// Give it to `HttpModule(config: ...)`, or replace the binding at run time
/// with an override (`Singleton<HttpConfig>(...)`) to read the port from the
/// environment.
final class HttpConfig {
  /// Creates the configuration.
  const HttpConfig({
    this.address = 'localhost',
    this.port = 8080,
    this.maxBodyBytes = 1048576,
    this.debug = false,
  });

  /// What the adapter binds to: a host name or an address object, whatever
  /// the adapter understands.
  final Object address;

  /// The port; 0 asks the adapter for an ephemeral port.
  final int port;

  /// The largest request body the body readers accept; more is a 413.
  final int maxBodyBytes;

  /// Whether a 500 response shows the error and its stack trace. Never
  /// enable it in production.
  final bool debug;
}
