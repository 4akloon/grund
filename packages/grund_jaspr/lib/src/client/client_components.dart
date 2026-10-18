import 'package:jaspr/jaspr.dart';

import 'client_component.dart';

/// The list of client components shared by the server and the browser.
///
/// Constant and never throwing: the side that uses the list reports
/// [problems] in its own way.
final class ClientComponents {
  /// Creates the list from [components].
  const ClientComponents(this.components);

  static final RegExp _validName = RegExp(r'^[a-z0-9_-]+$');

  /// The registered components, in declaration order.
  final List<ClientComponent<Component>> components;

  /// What is wrong with the list, one text per problem; empty when all is well.
  ///
  /// Names a duplicate island name, two entries for one component type, an
  /// entry whose type was inferred as `Component`, and an unusable name.
  List<String> get problems {
    final problems = <String>[];
    final names = <String>{};
    final types = <Type, String>{};
    for (final component in components) {
      final name = component.name;
      if (!_validName.hasMatch(name)) {
        problems.add("client component name '$name' must match [a-z0-9_-]+");
      }
      if (!names.add(name)) {
        problems.add("client component name '$name' is registered twice");
      }
      if (component.type == Component) {
        problems.add(
          "client component '$name' has no explicit type argument: write "
          "ClientComponent<YourComponent>('$name', ...)",
        );
      }
      final first = types[component.type];
      if (first == null) {
        types[component.type] = name;
      } else if (component.type != Component) {
        problems.add(
          "client component '$name' registers ${component.type}, "
          "which '$first' already registers",
        );
      }
    }
    return problems;
  }
}
