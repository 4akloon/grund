import 'binding.dart';
import 'key.dart';
import 'module_identity.dart';

/// Names one binding of the graph: the module that declares it and its key.
typedef BindingId = (ModuleIdentity module, Key<Object> key);

/// A binding together with the module that declares it.
final class VisibleBinding {
  /// Creates the pair.
  const VisibleBinding(this.owner, this.binding);

  /// The declaring module.
  final ModuleIdentity owner;

  /// The binding.
  final Binding<Object> binding;

  /// Identifies the binding in the whole graph.
  BindingId get id => (owner, binding.key);
}
