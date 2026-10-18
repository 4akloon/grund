import 'package:jaspr/server.dart';

/// Holds the options a `JasprModule` installed, so its shutdown gives back
/// exactly those.
///
/// The module is constant and has no state of its own; the lease lives in
/// the application's container instead.
final class ClientOptionsLease {
  /// The result of `JasprSetup.initialize`; `null` before the module's
  /// `onInit` and when the application has no client components.
  ServerOptions? installed;
}
