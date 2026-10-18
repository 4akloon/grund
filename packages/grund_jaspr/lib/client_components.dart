/// The list of client components, shared by the server and the browser.
///
/// Pure data: this library imports only `package:jaspr/jaspr.dart`, so one
/// file can be compiled for the server and for the browser. Write it once:
///
/// ```dart
/// // lib/clients.dart
/// import 'package:grund_jaspr/client_components.dart';
/// import 'src/web/counter.dart';
///
/// const clients = ClientComponents([
///   ClientComponent<Counter>(
///     'counter',
///     encode: Counter.toParams,
///     decode: Counter.fromParams,
///   ),
///   ClientComponent<Clock>('clock', decode: Clock.fromParams), // no params
/// ]);
/// ```
library;

export 'src/client/client_component.dart';
export 'src/client/client_components.dart';
export 'src/client/client_entry.dart';
