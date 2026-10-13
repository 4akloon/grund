import 'package:code_builder/code_builder.dart';

import '../model/component_reference.dart';
import '../model/enhancers_model.dart';
import 'import_allocator.dart';
import 'type_emitter.dart';

/// Writes [EnhancersModel]s as `const Enhancers(...)` of `Use<T>()`
/// components, resolved from the module's injector.
abstract final class EnhancersEmitter {
  /// `const Enhancers(guards: [Use<AuthGuard>()])`, or `null` when
  /// [enhancers] is empty.
  static Expression? enhancers(EnhancersModel enhancers) {
    final lists = {
      'guards': enhancers.guards,
      'interceptors': enhancers.interceptors,
      'pipes': enhancers.pipes,
      'filters': enhancers.filters,
    };
    if (lists.values.every((list) => list.isEmpty)) return null;
    return refer(
      'Enhancers',
      ImportAllocator.dartnest,
    ).constInstance(const [], {
      for (final MapEntry(:key, :value) in lists.entries)
        if (value.isNotEmpty) key: literalList(value.map(_use)),
    });
  }

  static Expression _use(ComponentReference component) => TypeReference(
    (b) => b
      ..symbol = 'Use'
      ..url = ImportAllocator.dartnest
      ..types.add(TypeEmitter.reference(component.type)),
  ).newInstance(const []);
}
