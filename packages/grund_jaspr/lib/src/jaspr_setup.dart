import 'package:jaspr/server.dart';

import 'error/jaspr_error.dart';

/// Initializes Jaspr's process-wide state once, for every application of
/// the process.
abstract final class JasprSetup {
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
}
