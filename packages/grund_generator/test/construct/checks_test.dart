import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/model/binding_key.dart';
import 'package:grund_generator/src/model/injectable_model.dart';
import 'package:grund_generator/src/model/lifetime.dart';
import 'package:grund_generator/src/model/provider_model.dart';
import 'package:grund_generator/src/model/package_model.dart';
import 'package:grund_generator/src/diagnostic/source_location.dart';
import 'package:grund_generator/src/model/constructor_model.dart';
import 'package:grund_generator/src/model/type_kind.dart';
import 'package:grund_generator/src/model/type_model.dart';
import 'package:grund_generator/src/model/unsupported_use.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';
import '../helpers/graph_models.dart';

void main() {
  late PackageModel unsupported; // Set in setUpAll.

  setUpAll(() async {
    unsupported = await FixturePackage.open(
      'cases_app',
    ).collect(['lib/unsupported.dart', 'lib/modules/basic.dart']);
  });

  List<String> codes(PackageModel package) => [
    for (final d in const GrundGenerator.core().generate(package).diagnostics)
      d.code.id,
  ];

  test('a cycle between two bindings is circular_dependency', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
        GraphModels.provider('B', needs: ['A']),
      ],
    );

    expect(
      codes(GraphModels.package([module])),
      contains('circular_dependency'),
    );
  });

  test('a singleton on a call-scoped binding is captive_dependency', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
        GraphModels.provider('B', lifetime: Lifetime.scoped),
      ],
    );

    expect(codes(GraphModels.package([module])), ['captive_dependency']);
  });

  test('a dependency nobody binds is missing_provider', () {
    final module = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );

    expect(codes(GraphModels.package([module])), ['missing_provider']);
  });

  test('a binding exported by another module needs an import', () {
    final lib = GraphModels.module(
      'Lib',
      providers: [GraphModels.provider('B')],
      exports: [GraphModels.export('B')],
    );
    final app = GraphModels.module(
      'App',
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );
    final imported = GraphModels.module(
      'App',
      imports: [GraphModels.reference('Lib')],
      providers: [
        GraphModels.provider('A', needs: ['B']),
      ],
    );

    expect(codes(GraphModels.package([lib, app])), ['missing_provider']);
    expect(codes(GraphModels.package([lib, imported])), isEmpty);
  });

  test('two bindings of one key are duplicate_binding', () {
    final module = GraphModels.module(
      'App',
      providers: [GraphModels.provider('A'), GraphModels.provider('A')],
    );

    expect(codes(GraphModels.package([module])), ['duplicate_binding']);
  });

  test('a Bind to Object is invalid_bind', () {
    final provider = GraphModels.provider('Clock');
    final bound = ProviderModel(
      BindingKey(
        const TypeModel(
          name: 'Object',
          kind: TypeKind.interface,
          libraryUri: 'dart:core',
        ),
      ),
      provider.injectable,
    );
    final module = GraphModels.module('App', providers: [bound]);

    expect(codes(GraphModels.package([module])), ['invalid_bind']);
  });

  test('an unresolved scope and a broken @Provides are reported', () {
    final scoped = InjectableModel(
      type: GraphModels.type('A'),
      lifetime: Lifetime.singleton,
      isAnnotated: true,
      location: const SourceLocation('lib/app.dart', 1, 1),
      constructor: const ConstructorModel([]),
      scopeProblem: 'The scope is not a constant Scope value.',
    );
    final module = GraphModels.module(
      'App',
      providers: [ProviderModel(scoped.key, scoped)],
      provides: [GraphModels.provides('App', 'B', problem: 'No.')],
    );

    expect(codes(GraphModels.package([module])).toSet(), {
      'invalid_scope',
      'invalid_provides',
    });
  });

  test('unsupported uses become unsupported_use', () {
    final package = PackageModel(
      packageName: 'app',
      languageVersion: Version(3, 8, 0),
      unsupportedUses: const [
        UnsupportedUse(
          element: 'Mixed',
          reason: 'Inherited.',
          location: SourceLocation('lib/app.dart', 4, 2),
        ),
      ],
    );

    expect(codes(package), ['unsupported_use']);
  });

  test('the cases_app fixture reports unsupported uses and bad scopes', () {
    expect(
      codes(unsupported),
      containsAll(['unsupported_use', 'invalid_scope']),
    );
  });
}
