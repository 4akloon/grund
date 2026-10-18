import 'package:logging/logging.dart';

import '../jaspr_config.dart';
import '../site/static_files.dart';

/// Warns at start when the client bundle the pages point to is not built.
abstract final class ClientBundleCheck {
  static final Logger _log = Logger('grund.jaspr');

  /// Logs a `WARNING` on `grund.jaspr` when `config.clients` is set and the
  /// bundle file is not in [files]; starting goes on, since the bundle may be
  /// built while the application runs.
  static void warnIfMissing(JasprConfig config, StaticFiles files) {
    if (config.clients == null) return;
    const directory = JasprConfig.clientDirectory;
    const script = JasprConfig.clientScript;
    if (files.find([directory, script]) != null) return;
    _log.warning(
      'The client bundle $directory/$script is not in '
      '${config.staticDirectory}; pages with client components will not '
      'hydrate. Build it with `grund bundle`.',
    );
  }
}
