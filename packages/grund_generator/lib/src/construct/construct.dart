import '../collector/collection_context.dart';
import '../diagnostic/diagnostic.dart';
import '../model/binding_model.dart';
import '../model/extension_model.dart';
import '../model/package_model.dart';
import '../model/provider_model.dart';
import 'construct_annotations.dart';
import 'generated_unit.dart';
import 'provider_claims.dart';

/// One kind of generated code, with the phases the generator runs in this
/// order:
///
/// 1. [annotations] and [collect], while `PackageCollector` reads the
///    package: the construct names the annotations it reads and reads them
///    into an [ExtensionModel] of its own, kept in
///    [PackageModel.extensions];
/// 2. [claimProvider], before the checks: a construct may take over a
///    provider class of a module and give its binding, which the graph
///    checks use;
/// 3. [validate]: the problems that make the package impossible to
///    generate;
/// 4. [generate], only when no construct reported a problem.
///
/// The core has `ModuleConstruct`; other packages add their own, and the
/// drivers compile the set in statically.
abstract base class Construct {
  /// Creates the construct.
  const Construct();

  /// The annotations this construct reads; none by default.
  ConstructAnnotations get annotations => const ConstructAnnotations();

  /// The model of this construct's annotations in [context], or `null`
  /// when it keeps none (the default).
  ExtensionModel? collect(CollectionContext context) => null;

  /// The binding of [provider] when this construct claims it, or `null`
  /// (the default) when the class is an ordinary provider.
  ///
  /// A claimed provider is bound as the result says: its key, lifetime
  /// and dependencies are what the graph checks see, and its
  /// [BindingModel.lookups] must be visible in the module.
  BindingModel? claimProvider(ProviderModel provider, PackageModel package) =>
      null;

  /// The problems that make [package] impossible to generate; [claims] are
  /// the providers the constructs claimed.
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims);

  /// The output for [package]; called only when no construct reported a
  /// diagnostic.
  Iterable<GeneratedUnit> generate(PackageModel package, ProviderClaims claims);
}
