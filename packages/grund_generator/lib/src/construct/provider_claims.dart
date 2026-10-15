import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/binding_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provider_model.dart';
import 'construct.dart';

/// The providers of a package's modules that constructs claimed
/// (`Construct.claimProvider`), with the bindings they gave.
final class ProviderClaims {
  ProviderClaims._(this._bindings, this.conflicts);

  /// No provider is claimed.
  ProviderClaims.none() : this._(Map.identity(), const []);

  /// Asks every construct, in order, about every provider of every module
  /// of [package].
  factory ProviderClaims.collect(
    PackageModel package,
    List<Construct> constructs,
  ) {
    final bindings = Map<ProviderModel, BindingModel>.identity();
    final conflicts = <Diagnostic>[];
    for (final module in package.modules) {
      for (final provider in module.providers) {
        final claims = [
          for (final construct in constructs)
            if (construct.claimProvider(provider, package) case final binding?)
              (construct: construct, binding: binding),
        ];
        if (claims.firstOrNull case final claim?) {
          bindings[provider] = claim.binding;
        }
        if (claims.length > 1) {
          conflicts.add(_conflict(module, provider, claims));
        }
      }
    }
    return ProviderClaims._(bindings, conflicts);
  }

  final Map<ProviderModel, BindingModel> _bindings;

  /// One diagnostic per provider that more than one construct claimed.
  final List<Diagnostic> conflicts;

  /// The binding a construct gave [provider], or `null` when none claimed
  /// it.
  BindingModel? claimed(ProviderModel provider) => _bindings[provider];

  /// The bindings [module] owns: those of its providers, as claimed or
  /// [ProviderModel.binding], then those of its `@Provides` methods.
  List<BindingModel> bindingsOf(ModuleModel module) => [
    for (final provider in module.providers)
      _bindings[provider] ?? provider.binding,
    ...module.providedBindings,
  ];

  static Diagnostic _conflict(
    ModuleModel module,
    ProviderModel provider,
    List<({Construct construct, BindingModel binding})> claims,
  ) => Diagnostic(
    DiagnosticCode.conflictingProviderClaim,
    provider.injectable.location,
    '${provider.injectable.type}, a provider of module ${module.type}, is '
    'claimed by [${claims.map((c) => c.construct.runtimeType).join(', ')}]; '
    'a class can be only one of these kinds.',
  );
}
