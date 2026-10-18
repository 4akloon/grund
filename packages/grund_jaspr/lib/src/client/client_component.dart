import 'package:jaspr/jaspr.dart';

import 'client_entry.dart';

/// A component that hydrates in the browser, registered under a [name].
///
/// Write the type argument explicitly (the counter example takes the type
/// `Counter`). The server matches that type against the rendered components,
/// and it is inferred as `Component` when left out.
final class ClientComponent<T extends Component> {
  /// Registers a component under [name] (`[a-z0-9_-]+`).
  ///
  /// [decode] builds it in the browser from the marker's parameters; [encode]
  /// gives those parameters on the server and is left out for a component
  /// without any.
  const ClientComponent(this.name, {required this._decode, this._encode});

  /// The island name, as written in the page markup.
  final String name;

  // Private: reading a `Function(T)` field through a
  // `ClientComponent<Component>` fails the covariance check; [withType] is
  // the only way in.
  final T Function(Map<String, Object?> params) _decode;
  final Map<String, Object?> Function(T component)? _encode;

  /// The component type this entry registers.
  Type get type => T;

  /// Runs [body] with the entry typed by the component's real type.
  R withType<R>(R Function<C extends Component>(ClientEntry<C> entry) body) =>
      body<T>(ClientEntry<T>(name, _decode, _encode));
}
