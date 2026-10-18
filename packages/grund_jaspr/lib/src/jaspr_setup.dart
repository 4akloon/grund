import 'package:jaspr/server.dart';

import 'client/server_client_options.dart';
import 'error/jaspr_error.dart';
import 'jaspr_config.dart';

/// Initializes Jaspr's process-wide state once, for every application of
/// the process.
abstract final class JasprSetup {
  /// The options the latest [initialize] installed; being identical to it is
  /// what makes the options ours.
  static ServerOptions? _latest;

  /// Initializes Jaspr unless it is initialized already (by another
  /// application of the process, or by `main` with its own options); throws
  /// [JasprSetupError] when it was initialized to render in other isolates.
  static void ensureInitialized() {
    if (!Jaspr.isInitialized) {
      Jaspr.initializeApp();
      return;
    }
    if (Jaspr.useIsolates) {
      throw const JasprSetupError(
        'Jaspr was initialized with useIsolates: true. A page reads the call '
        'scope of its request, which another isolate cannot reach; call '
        'Jaspr.initializeApp() without useIsolates, or not at all.',
      );
    }
  }

  /// Installs the client options of `config.clients` and returns them, or
  /// only [ensureInitialized] and returns `null` when there are none.
  ///
  /// Throws [JasprSetupError] when Jaspr was initialized by someone else with
  /// client options or styles (anything but the default options), or to
  /// render in other isolates. Pass the result to
  /// [release] on shutdown.
  static ServerOptions? initialize(JasprConfig config) {
    ensureInitialized();
    if (config.clients == null) return null;
    final current = Jaspr.options;
    final ours = identical(current, _latest);
    final bare =
        current.clients?.isNotEmpty != true &&
        current.clientId == null &&
        current.stylesId == null &&
        current.styles == null;
    if (!ours && !bare) {
      throw const JasprSetupError(
        'Jaspr was initialized with options of its own (client components, a '
        'client script or styles). A JasprModule '
        'with JasprConfig.clients installs them itself; remove the '
        'Jaspr.initializeApp(options: ServerOptions(...)) call from main.',
      );
    }
    final options = ServerClientOptions.of(config);
    Jaspr.initializeApp(
      options: options,
      allowedPathSuffixes: Jaspr.allowedPathSuffixes,
    );
    return _latest = options;
  }

  /// Gives back the default options when [installed] (the result of
  /// [initialize]) is still what Jaspr uses; does nothing otherwise, as the
  /// options of a newer application stay.
  static void release(ServerOptions? installed) {
    if (installed == null || !identical(Jaspr.options, installed)) return;
    Jaspr.initializeApp(allowedPathSuffixes: Jaspr.allowedPathSuffixes);
    _latest = null;
  }
}
