import 'package:grund/grund.dart';

/// How the HTTP server listens and what it accepts.
///
/// Give it to `HttpModule(config: ...)`, or read the address and the port
/// from the environment with [HttpConfig.fromEnvironment] (in a module,
/// `HttpModule.fromEnvironment()`).
final class HttpConfig {
  /// Creates the configuration.
  const HttpConfig({
    this.address = 'localhost',
    this.port = 8080,
    this.maxBodyBytes = 1048576,
    this.debug = false,
    this.accessLog = true,
  });

  /// The configuration with the address from `HOST` and the port from `PORT`
  /// (0 to 65535) when they are set, and everything else from [defaults].
  ///
  /// Throws [InvalidVariableError] for an empty `HOST`, one with white space,
  /// or a bad `PORT`.
  factory HttpConfig.fromEnvironment(
    Environment environment, {
    HttpConfig defaults = const HttpConfig(),
  }) => HttpConfig(
    address: _host(environment) ?? defaults.address,
    port: environment.integer(
      portVariable,
      fallback: defaults.port,
      min: 0,
      max: 65535,
    ),
    maxBodyBytes: defaults.maxBodyBytes,
    debug: defaults.debug,
    accessLog: defaults.accessLog,
  );

  /// The variable [HttpConfig.fromEnvironment] reads the address from.
  static const hostVariable = 'HOST';

  /// The variable [HttpConfig.fromEnvironment] reads the port from.
  static const portVariable = 'PORT';

  static final RegExp _whiteSpace = RegExp(r'\s');

  static String? _host(Environment environment) {
    if (!environment.has(hostVariable)) return null;
    final host = environment.string(hostVariable);
    if (host.isEmpty || _whiteSpace.hasMatch(host)) {
      throw const InvalidVariableError(
        name: hostVariable,
        expected: 'a host name or an IP address',
      );
    }
    return host;
  }

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

  /// Whether every answered request is logged as one `INFO` line on the
  /// logger `grund.access`: `GET /tasks/1 200 12ms`.
  final bool accessLog;
}
