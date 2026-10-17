import 'package:grund/grund.dart' show Environment;
import 'package:grund_http/grund_http.dart' show HttpConfig;

import 'adapter_kind.dart';
import 'module_style.dart';

/// The command line of `bin/main.dart`: `[--explicit] [--shelf]
/// [--only=<runner>,...]`, and the address and port from the `HOST` and
/// `PORT` environment variables (`localhost` and 8080 by default).
final class ServerOptions {
  /// Creates the options.
  const ServerOptions({
    this.style = ModuleStyle.annotations,
    this.adapter = AdapterKind.io,
    this.address = 'localhost',
    this.port = 8080,
  });

  /// Reads [arguments] and [environment]; throws a [FormatException] for
  /// an unknown argument and an `EnvironmentError` for an invalid `HOST` or
  /// `PORT`. `--only=...` is left to `Runners.fromArgs`.
  factory ServerOptions.parse(List<String> arguments, Environment environment) {
    final unknown = arguments.where(
      (a) => !_flags.contains(a) && !a.startsWith('--only='),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('Unknown argument ${unknown.first}.\n$usage');
    }
    final http = HttpConfig.fromEnvironment(environment);
    return ServerOptions(
      style: arguments.contains('--explicit')
          ? ModuleStyle.explicit
          : ModuleStyle.annotations,
      adapter: arguments.contains('--shelf')
          ? AdapterKind.shelf
          : AdapterKind.io,
      address: http.address,
      port: http.port,
    );
  }

  /// How to call `bin/main.dart`.
  static const usage =
      'Usage: dart run bin/main.dart [--explicit] [--shelf] [--only=http]\n'
      '  --explicit  serve the module graph written with the explicit API\n'
      '  --shelf     serve with ShelfAdapter instead of IoAdapter\n'
      '  --only=...  start only the named runners\n'
      'The address is HOST and the port is PORT from the environment\n'
      '(localhost and 8080 by default).';

  static const _flags = {'--explicit', '--shelf'};

  /// The module graph to serve.
  final ModuleStyle style;

  /// The adapter to serve with.
  final AdapterKind adapter;

  /// The address to listen on.
  final Object address;

  /// The port to listen on.
  final int port;
}
