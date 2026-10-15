import '../diagnostic/diagnostic.dart';
import '../diagnostic/diagnostic_code.dart';
import '../model/binding_model.dart';
import '../model/module_model.dart';
import '../model/package_model.dart';
import '../model/provider_model.dart';
import 'construct.dart';
import 'provider_claim.dart';

/// The providers of a package's modules that constructs claimed
/// (`Construct.claimProvider`), with the bindings they gave.
final class ProviderClaims {
  ProviderClaims._(this._claims, this._owners, this.conflicts);

  /// No provider is claimed.
  ProviderClaims.none() : this._(Map.identity(), Map.identity(), const []);

  /// Asks every construct, in order, about every provider of every module
  /// of [package].
  factory ProviderClaims.collect(
    PackageModel package,
    List<Construct> constructs,
  ) {
    final claimed = Map<ProviderModel, ProviderClaim>.identity();
    final owners = Map<ProviderModel, String>.identity();
    final conflicts = <Diagnostic>[];
    for (final module in package.modules) {
      for (final provider in module.providers) {
        final claims = [
          for (final construct in constructs)
            if (construct.claimProvider(provider, package) case final claim?)
              (construct: construct, claim: claim),
        ];
        if (claims.firstOrNull case final first?) {
          claimed[provider] = first.claim;
          owners[provider] = first.construct.name;
        }
        if (claims.length > 1) {
          conflicts.add(_conflict(module, provider, claims));
        }
      }
    }
    return ProviderClaims._(claimed, owners, conflicts);
  }

  final Map<ProviderModel, ProviderClaim> _claims;

  final Map<ProviderModel, String> _owners;

  /// One diagnostic per provider that more than one construct claimed.
  final List<Diagnostic> conflicts;

  /// Throws [StateError] naming the construct when a claimed binding has no
  /// [BindingModel.emission]: the module file cannot register it.
  void requireEmissions() {
    for (final MapEntry(key: provider, value: claim) in _claims.entries) {
      for (final binding in claim.bindings) {
        if (binding.emission != null) continue;
        throw StateError(
          'The construct ${_owners[provider]} claimed '
          '${provider.injectable.type} but gave its binding ${binding.key} '
          'no emission.',
        );
      }
    }
  }

  /// The claim a construct made for [provider], or `null` when none
  /// claimed it.
  ProviderClaim? claimed(ProviderModel provider) => _claims[provider];

  /// The bindings [module] owns: those of its providers (the bindings of
  /// their claims, or [ProviderModel.binding]), then those of its
  /// `@Provides` methods.
  List<BindingModel> bindingsOf(ModuleModel module) => [
    for (final provider in module.providers)
      ...(_claims[provider]?.bindings ?? [provider.binding]),
    ...module.providedBindings,
  ];

  static Diagnostic _conflict(
    ModuleModel module,
    ProviderModel provider,
    List<({Construct construct, ProviderClaim claim})> claims,
  ) => Diagnostic(
    DiagnosticCode.conflictingProviderClaim,
    provider.injectable.location,
    '${provider.injectable.type}, a provider of module ${module.type}, is '
    'claimed by [${claims.map((c) => c.construct.name).join(', ')}]; '
    'a class can be only one of these kinds.',
  );
}
