import 'package:jaspr/server.dart';

import '../jaspr_config.dart';
import 'client_component.dart';

/// Turns the neutral list of client components into Jaspr's server options.
abstract final class ServerClientOptions {
  /// The options that make Jaspr mark the components of `config.clients` and
  /// add the `clientId` script to the pages that contain one.
  ///
  /// An island's parameters are written into an HTML comment (`data=`) and
  /// cannot end it with `-->`: Jaspr guarantees that (`ClientTarget(params:)`
  /// goes through `jsonEncode` and `DomValidator.escapeMarkerText`, which
  /// escapes `&`, `<` and `>`), so nothing is escaped here. Check this again
  /// on a Jaspr upgrade; `test/hydration_markup_test.dart` (a parameter
  /// holding `-->`) is the guard.
  static ServerOptions of(JasprConfig config) => ServerOptions(
    clientId: config.clientId,
    clients: {
      for (final component
          in config.clients?.components ?? const <ClientComponent<Component>>[])
        ..._target(component),
    },
  );

  static Map<Type, ClientTarget> _target(
    ClientComponent<Component> component,
  ) => component.withType(
    <C extends Component>(entry) => {
      C: ClientTarget<C>(entry.name, params: entry.encode),
    },
  );
}
