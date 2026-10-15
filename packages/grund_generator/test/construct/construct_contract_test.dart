import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';
import '../helpers/graph_models.dart';

/// Claims the provider of class [type] with [binding].
final class _Claiming extends Construct {
  const _Claiming(this.type, this.binding);

  final String type;

  final BindingModel binding;

  @override
  BindingModel? claimProvider(ProviderModel provider, PackageModel package) =>
      provider.injectable.type.name == type ? binding : null;

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) =>
      const [];

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => const [];
}

/// Collects the URIs of the libraries it is given.
final class _Collecting extends Construct {
  const _Collecting();

  @override
  _Uris collect(CollectionContext context) =>
      _Uris([for (final library in context.libraries) '${library.uri}']);

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) =>
      const [];

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => const [];
}

final class _Uris implements ExtensionModel {
  const _Uris(this.uris);

  final List<String> uris;

  @override
  bool get isEmpty => uris.isEmpty;
}

const _lookupAt = SourceLocation('lib/app.dart', 7, 3);

BindingModel _binding(
  String name, {
  List<String> needs = const [],
  List<String> looksUp = const [],
  Lifetime lifetime = Lifetime.singleton,
}) => BindingModel(
  key: GraphModels.key(name),
  lifetime: lifetime,
  dependencies: [for (final n in needs) GraphModels.need(GraphModels.key(n))],
  location: const SourceLocation('lib/app.dart', 1, 1),
  lookups: [
    for (final n in looksUp) BindingLookup(GraphModels.key(n), _lookupAt),
  ],
);

List<Diagnostic> _diagnostics(
  List<ProviderModel> providers,
  List<Construct> constructs,
) => GrundGenerator([const ModuleConstruct(), ...constructs])
    .generate(
      GraphModels.package([GraphModels.module('App', providers: providers)]),
    )
    .diagnostics;

void main() {
  test('a claimed provider is checked with the binding of its claim', () {
    final diagnostics = _diagnostics(
      [GraphModels.provider('A')],
      [
        _Claiming('A', _binding('A', needs: ['B'])),
      ],
    );

    expect([for (final d in diagnostics) d.code.id], ['missing_provider']);
  });

  test('a lookup of a claimed binding must be visible in the module', () {
    final missing = _diagnostics(
      [GraphModels.provider('A')],
      [
        _Claiming('A', _binding('A', looksUp: ['B'])),
      ],
    );
    final bound = _diagnostics(
      [GraphModels.provider('A'), GraphModels.provider('B')],
      [
        _Claiming('A', _binding('A', looksUp: ['B'])),
      ],
    );

    expect(
      missing.single.toString(),
      'lib/app.dart:7:3: error: No provider for B in module App (needed by '
      'A). [missing_provider]',
    );
    expect(bound, isEmpty);
  });

  test('a lookup is no edge of the dependency graph', () {
    final diagnostics = _diagnostics(
      [
        GraphModels.provider('A'),
        GraphModels.provider('B', needs: ['A'], lifetime: Lifetime.scoped),
      ],
      [
        _Claiming('A', _binding('A', looksUp: ['B'])),
      ],
    );

    expect(diagnostics, isEmpty);
  });

  test('a provider claimed by two constructs is a conflict', () {
    final diagnostics = _diagnostics(
      [GraphModels.provider('A')],
      [_Claiming('A', _binding('A')), _Claiming('A', _binding('A'))],
    );

    expect(diagnostics.single.code, DiagnosticCode.conflictingProviderClaim);
    expect(diagnostics.single.message, contains('[_Claiming, _Claiming]'));
  });

  test('a construct collects its model into the package', () async {
    final fixture = FixturePackage.open('cases_app');
    final libraries = await fixture.libraries([
      'lib/modules/basic.dart',
      'lib/constants.dart',
    ]);
    final package = PackageCollector(
      fixture.name,
      fixture.root,
      constructs: const [_Collecting()],
    ).collect(libraries);

    expect(package.extensionModel<_Uris>()?.uris, [
      'package:cases_app/constants.dart',
      'package:cases_app/modules/basic.dart',
    ]);
  });

  test('an extension with content makes the package non-empty', () {
    PackageModel package(List<String> uris) => PackageModel(
      packageName: 'app',
      languageVersion: GraphModels.package([]).languageVersion,
      extensions: [_Uris(uris)],
    );

    expect(package([]).isEmpty, isTrue);
    expect(package(['package:app/app.dart']).isEmpty, isFalse);
    expect(package([]).extensionModel<_Uris>(), isNotNull);
    expect(GraphModels.package([]).extensionModel<_Uris>(), isNull);
  });

  test('construct annotations join their member annotations', () {
    const one = ConstructAnnotations(
      classes: {
        'Job': {'Every'},
      },
      injectable: {'Job'},
    );
    const two = ConstructAnnotations(
      classes: {
        'Job': {'Once'},
        'Channel': {},
      },
    );

    final both = one.union(two);

    expect(both.classes, {
      'Job': {'Every', 'Once'},
      'Channel': <String>{},
    });
    expect(both.injectable, {'Job'});
    expect(both.names, {'Job', 'Every', 'Once', 'Channel'});
  });
}
