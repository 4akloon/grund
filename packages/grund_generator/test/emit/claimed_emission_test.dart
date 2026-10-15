import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';
import 'package:test/test.dart';

import '../helpers/graph_models.dart';

const _output = 'lib/app.module.g.dart';

/// Claims the provider `Tasks` and registers it with [emission].
final class _Claiming extends Construct {
  const _Claiming(this.emission);

  final Expression? emission;

  @override
  String get name => 'claiming';

  @override
  ProviderClaim? claimProvider(ProviderModel provider, PackageModel package) =>
      provider.injectable.type.name == 'Tasks'
      ? ProviderClaim([
          BindingModel(
            key: GraphModels.key('Tasks'),
            lifetime: Lifetime.singleton,
            dependencies: const [],
            location: provider.injectable.location,
            emission: emission,
          ),
        ])
      : null;

  @override
  Iterable<Diagnostic> validate(PackageModel package, ProviderClaims claims) =>
      const [];

  @override
  Iterable<GeneratedUnit> generate(
    PackageModel package,
    ProviderClaims claims,
  ) => const [];
}

PackageModel _package() => GraphModels.package([
  GraphModels.module(
    'AppModule',
    providers: [GraphModels.provider('Clock'), GraphModels.provider('Tasks')],
  ),
]);

GenerationResult _generate(Expression? emission) => GrundGenerator([
  const ModuleConstruct(),
  _Claiming(emission),
]).generate(_package());

void main() {
  test('a claimed binding is written as its construct gave it', () {
    final result = _generate(
      refer('Singleton', 'package:grund/grund.dart').newInstance(
        [
          Method(
            (b) => b
              ..requiredParameters.add(Parameter((p) => p..name = 'i'))
              ..lambda = true
              ..body = refer(
                'TasksFactory',
                'package:app/tasks.dart',
              ).newInstance([]).code,
          ).closure,
        ],
        const {},
        [refer('Tasks', 'package:app/app.dart')],
      ),
    );
    final source = result.files[_output]!;

    expect(result.diagnostics, isEmpty);
    expect(
      source,
      contains('grund.Singleton<i1.Tasks>((i) => i2.TasksFactory())'),
    );
  });

  test('the claimed binding keeps the place of its provider', () {
    final source = _generate(refer('claimed', 'package:app/x.dart')).files;

    expect(
      source[_output],
      contains(
        'grund.Singleton<i1.Clock>('
        '(i) => i1.Clock(), dependsOn: const []),\n    i2.claimed,',
      ),
    );
  });

  test('a claimed binding without an emission names its construct', () {
    expect(
      () => _generate(null),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('claiming'), contains('Tasks'), contains('emission')),
        ),
      ),
    );
  });

  test('the bindings of a claim cannot be changed afterwards', () {
    final bindings = [
      BindingModel(
        key: GraphModels.key('Tasks'),
        lifetime: Lifetime.singleton,
        dependencies: const [],
        location: const SourceLocation('lib/app.dart', 1, 1),
      ),
    ];
    final claim = ProviderClaim(bindings);

    bindings.clear();

    expect(claim.bindings, hasLength(1));
    expect(claim.bindings.clear, throwsUnsupportedError);
  });
}
