import 'package:code_builder/code_builder.dart';

import '../diagnostic/source_location.dart';
import 'binding_key.dart';
import 'binding_lookup.dart';
import 'dependency_model.dart';
import 'lifetime.dart';

/// A binding a module owns, as the graph checks see it: its key, lifetime
/// and what it resolves, whether it comes from a class or a `@Provides`
/// method.
final class BindingModel {
  /// Creates the binding.
  const BindingModel({
    required this.key,
    required this.lifetime,
    required this.dependencies,
    required this.location,
    this.lookups = const [],
    this.emission,
  });

  /// What the binding is looked up by.
  final BindingKey key;

  /// How long the instances live.
  final Lifetime lifetime;

  /// What the factory resolves, in parameter order.
  final List<DependencyModel> dependencies;

  /// Where the binding is declared.
  final SourceLocation location;

  /// What the instance looks up while it is used, in addition to
  /// [dependencies]; a construct that claims a provider sets it.
  final List<BindingLookup> lookups;

  /// How the module's generated code registers this binding, for a binding
  /// a construct gave through a claim; `null` for the bindings the module
  /// construct writes itself (provider classes and `@Provides` methods).
  ///
  /// It names declarations with `refer(name, url)`, so the import
  /// allocator of the file it is written into imports them.
  final Expression? emission;
}
