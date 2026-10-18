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
    button(onClick: () => setState(() => _value--), [Component.text('−')]),
    span([Component.text('${component.label}: $_value')]),
    button(onClick: () => setState(() => _value++), [Component.text('+')]),
  ]);
}
