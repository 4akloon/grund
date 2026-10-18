/// The browser entry of a hydrated site.
///
/// The entry point of the client bundle is three lines
/// (`lib/main.client.dart`, the Jaspr convention):
///
/// ```dart
/// import 'package:grund_jaspr/client.dart';
/// import 'clients.dart';
///
/// void main() => GrundClient.run(clients);
/// ```
///
/// where `clients` is the [ClientComponents] list declared in
/// `package:grund_jaspr/client_components.dart` and also given to the server
/// as `JasprConfig(clients: clients)`. Compile it with `grund bundle`.
///
/// This library imports `package:jaspr/client.dart`, which does not load on
/// the Dart VM, so it is for the browser only.
library;

export 'src/client/grund_client.dart';
export 'client_components.dart';
