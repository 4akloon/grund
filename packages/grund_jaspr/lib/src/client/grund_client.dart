import 'package:jaspr/client.dart';

import 'client_component.dart';
import 'client_components.dart';

/// Starts the hydration of the islands the server marked in the page.
abstract final class GrundClient {
  /// Registers [clients] with Jaspr and hydrates the page.
  ///
  /// Throws a [StateError] listing the problems when [clients] is not valid;
  /// there is no `GrundError` in the browser.
  static void run(ClientComponents clients) {
    final problems = clients.problems;
    if (problems.isNotEmpty) {
      throw StateError('Invalid client components:\n${problems.join('\n')}');
    }
    Jaspr.initializeApp(
      options: ClientOptions(
        clients: {
          for (final component in clients.components) ..._loadersOf(component),
        },
      ),
    );
    runApp(const ClientApp());
  }

  // A map, not a [ClientLoader], so that the type-erased entry can be
  // returned from the generic callback of [ClientComponent.withType].
  static Map<String, ClientLoader> _loadersOf(
    ClientComponent<Component> component,
  ) => component.withType(
    <C extends Component>(entry) => {
      entry.name: ClientLoader((params) => entry.decode(params)),
    },
  );
}
