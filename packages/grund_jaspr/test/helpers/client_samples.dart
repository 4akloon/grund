import 'package:jaspr/jaspr.dart';

/// A component with parameters, for the client registry tests.
class Counter extends StatelessComponent {
  /// Creates a counter that shows [label] and starts at [start].
  const Counter(this.start, this.label, {super.key});

  /// Reads the parameters of a marker.
  static Counter fromParams(Map<String, Object?> p) =>
      Counter(p['start']! as int, p['label']! as String);

  /// Gives the parameters of [c] for a marker.
  static Map<String, Object?> toParams(Counter c) => {
    'start': c.start,
    'label': c.label,
  };

  /// The initial value.
  final int start;

  /// The text next to the value.
  final String label;

  @override
  Component build(BuildContext context) => Component.text('$label $start');
}

/// A component with no registry entry.
class Plain extends StatelessComponent {
  /// Creates the component.
  const Plain({super.key});

  @override
  Component build(BuildContext context) => const Component.text('plain');
}

/// A subclass of [Counter], which the registry does not know.
class LoudCounter extends Counter {
  /// Creates the component.
  const LoudCounter(super.start, super.label, {super.key});
}
