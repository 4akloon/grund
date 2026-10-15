import 'adapter_kind.dart';
import 'module_style.dart';

/// The command line of `bin/main.dart`: `[--explicit] [--shelf]
/// [--only=<runner>,...]`, and the port from the `PORT` environment
/// variable (8080 by default).
final class ServerOptions {
  /// Creates the options.
  const ServerOptions({
    this.style = ModuleStyle.annotations,
    this.adapter = AdapterKind.io,
    this.port = defaultPort,
  });

  /// Reads [arguments] and [environment]; throws a [FormatException] for
  /// an unknown argument or a `PORT` outside 1 to 65535. `--only=...` is
  /// left to `Runners.fromArgs`.
  factory ServerOptions.parse(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    final unknown = arguments.where(
      (a) => !_flags.contains(a) && !a.startsWith('--only='),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown argument ${unknown.first}.\n$usage');
    }
    return ServerOptions(
      style: arguments.contains('--explicit')
          ? ModuleStyle.explicit
          : ModuleStyle.annotations,
      adapter: arguments.contains('--shelf')
          ? AdapterKind.shelf
          : AdapterKind.io,
      port: _port(environment['PORT']),
    );
  }

  /// The port without `PORT`.
  static const defaultPort = 8080;

  /// How to call `bin/main.dart`.
  static const usage =
      'Usage: dart run bin/main.dart [--explicit] [--shelf] [--only=http]\n'
      '  --explicit  serve the module graph written with the explicit API\n'
      '  --shelf     serve with ShelfAdapter instead of IoAdapter\n'
      '  --only=...  start only the named runners\n'
      'The port is PORT from the environment, 8080 by default.';

  static const _flags = {'--explicit', '--shelf'};

  /// The module graph to serve.
  final ModuleStyle style;

  /// The adapter to serve with.
  final AdapterKind adapter;

  /// The port to listen on.
  final int port;

  static int _port(String? value) {
    if (value == null) return defaultPort;
    final port = int.tryParse(value);
    if (port == null || port < 1 || port > 65535) {
      throw FormatException('PORT must be 1 to 65535, not "$value".');
    }
    return port;
  }
}
