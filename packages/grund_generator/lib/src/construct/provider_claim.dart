import '../model/binding_model.dart';

/// What a construct gives for a provider class it claims
/// (`Construct.claimProvider`): the bindings the module gets in place of
/// the class binding.
///
/// The graph checks (visibility, duplicates, exports, cycles, captive
/// dependencies) see each of [bindings] as a binding of the module.
final class ProviderClaim {
  /// Creates the claim; [bindings] must not be empty.
  const ProviderClaim(this.bindings) : assert(bindings.length > 0);

  /// The bindings, in the order the module writes them.
  final List<BindingModel> bindings;
}
