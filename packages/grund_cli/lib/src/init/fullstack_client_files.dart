/// The files of the hydrated counter that `init --template fullstack` adds
/// to the pages: the island, its registry and the browser entry point.
abstract final class FullstackClientFiles {
  /// The client files of application [name] (relative path to content).
  ///
  /// [name] is interpolated into the files as is; `ProjectScaffold` checks
  /// that it is a valid Dart package name.
  static Map<String, String> files(String name) => {
    'lib/clients.dart': _clients,
    'lib/main.client.dart': _mainClient,
    'lib/src/pages/counter.dart': _counter,
  };

  static const _clients = '''
import 'package:grund_jaspr/client_components.dart';

import 'src/pages/counter.dart';

/// The islands of the pages, shared by the server and the browser bundle.
const clients = ClientComponents([
  ClientComponent<Counter>(
    'counter',
    encode: Counter.toParams,
    decode: Counter.fromParams,
  ),
]);
''';

  static const _mainClient = '''
import 'package:grund_jaspr/client.dart';

import 'clients.dart';

/// The browser entry point: `dart run grund_cli bundle` compiles it to
/// `web/client/`, which the server serves under `/static/client/`.
void main() => GrundClient.run(clients);
''';

  static const _counter = '''
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A counter hydrated in the browser: rendered by the server with [start],
/// then driven by its buttons.
///
/// Imports only Jaspr's web-safe libraries, because the browser bundle
/// compiles it.
final class Counter extends StatefulComponent {
  /// A counter named [label] that starts at [start].
  const Counter({required this.start, required this.label, super.key});

  /// Decodes the parameters the server wrote into the page.
  factory Counter.fromParams(Map<String, Object?> params) =>
      Counter(start: params['start'] as int, label: params['label'] as String);

  /// The parameters of [counter] for the page.
  static Map<String, Object?> toParams(Counter counter) => {
    'start': counter.start,
    'label': counter.label,
  };

  /// The value shown before the first click.
  final int start;

  /// What is counted.
  final String label;

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  late int _value = component.start; // component is set before initState.

  @override
  Component build(BuildContext context) => div(classes: 'counter', [
    button(onClick: () => setState(() => _value--), [Component.text('-')]),
    span([Component.text('\${component.label}: \$_value')]),
    button(onClick: () => setState(() => _value++), [Component.text('+')]),
  ]);
}
''';
}
