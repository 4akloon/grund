import 'package:jaspr/jaspr.dart';

/// One registered client component with its real component type [T].
///
/// Handed to the body of `ClientComponent.withType`, where [T] is the
/// component's own type, so [decode] and [encode] can be used without the
/// covariance check that reading them through `ClientComponent<Component>`
/// would fail.
final class ClientEntry<T extends Component> {
  /// Creates the entry; [encode] is absent for a component without parameters.
  const ClientEntry(this.name, this.decode, this.encode);

  /// The island name, as written in the page markup.
  final String name;

  /// Builds the component in the browser from the parameters of the marker.
  final T Function(Map<String, Object?> params) decode;

  /// Gives the parameters of [component] on the server, or null when the
  /// component takes none.
  final Map<String, Object?> Function(T component)? encode;
}
