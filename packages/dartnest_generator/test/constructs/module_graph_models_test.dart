import 'package:dartnest_generator/src/construct/dartnest_generator.dart';
import 'package:dartnest_generator/src/constructs/module_construct.dart';
import 'package:dartnest_generator/src/diagnostic/source_location.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:dartnest_generator/src/model/module_export.dart';
import 'package:dartnest_generator/src/model/module_model.dart';
import 'package:dartnest_generator/src/model/module_reference.dart';
import 'package:dartnest_generator/src/model/package_model.dart';
import 'package:dartnest_generator/src/model/provider_key.dart';
import 'package:dartnest_generator/src/model/provider_model.dart';
import 'package:dartnest_generator/src/model/type_kind.dart';
import 'package:dartnest_generator/src/model/type_model.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

const _generator = DartnestGenerator([ModuleConstruct()]);

TypeModel _class(String name, [String library = 'package:app/app.dart']) =>
    TypeModel(name: name, kind: TypeKind.interface, libraryUri: library);

ModuleModel _module(
  String name, {
  String? id,
  List<ModuleReference> imports = const [],
  List<ProviderModel> providers = const [],
  List<ModuleExport> exports = const [],
  List<TypeModel> controllers = const [],
}) => ModuleModel(
  type: _class(name),
  id: id ?? name,
  location: SourceLocation('lib/app.dart', name.length, 7),
  imports: imports,
  providers: providers,
  exports: exports,
  controllers: controllers,
);

LocalModuleReference _local(String name) => LocalModuleReference(_class(name));

PackageModel _package(List<ModuleModel> modules) => PackageModel(
  packageName: 'app',
  languageVersion: Version(3, 8, 0),
  modules: modules,
);

TokenKey _token(ConstantValue expression) => TokenKey(
  valueType: _class('String', 'dart:core'),
  name: 'name',
  expression: expression,
);

void main() {
  group('module references', () {
    final billing = _module(
      'Shop',
      imports: [
        const OpaqueModuleReference(
          name: 'billingModule',
          libraryUri: 'package:billing/billing.dartnest.dart',
        ),
        const OpaqueModuleReference(
          name: 'forRoot',
          libraryUri: 'package:billing/billing.dart',
          enclosingName: 'BillingModule',
        ),
        _local('Other'),
      ],
    );

    test('another package is called through its own import', () {
      final result = _generator.generate(_package([billing, _module('Other')]));

      expect(
        result.library,
        contains('''
dartnest.Module shopModule() => dartnest.Module(
  id: 'Shop',
  imports: [i1.billingModule(), i2.BillingModule.forRoot(), otherModule()],
);
'''),
      );
      expect(
        result.library,
        contains("import 'package:billing/billing.dartnest.dart' as i1;"),
      );
      expect(
        result.library,
        contains("import 'package:billing/billing.dart' as i2;"),
      );
    });

    test('opaque imports take no part in cycle detection', () {
      final result = _generator.generate(_package([billing]));

      expect(result.diagnostics, isEmpty);
    });

    test('a duplicated import or export is written once', () {
      final shared = _module('Shared');
      final result = _generator.generate(
        _package([
          shared,
          _module(
            'Twice',
            imports: [_local('Shared'), _local('Shared')],
            exports: [
              ModuleReexport(_local('Shared')),
              ModuleReexport(_local('Shared')),
            ],
          ),
        ]),
      );

      expect(
        result.library,
        contains('''
dartnest.Module twiceModule() => dartnest.Module(
  id: 'Twice',
  imports: [sharedModule()],
  exports: [sharedModule()],
);
'''),
      );
    });

    test('a re-export of an opaque import is valid', () {
      const opaque = OpaqueModuleReference(
        name: 'explicitModule',
        libraryUri: 'package:app/explicit.dart',
      );
      final result = _generator.generate(
        _package([
          _module(
            'Wrapper',
            imports: [opaque],
            exports: [const ModuleReexport(opaque)],
          ),
        ]),
      );

      expect(result.diagnostics, isEmpty);
    });

    test('a controller is built by its generated function', () {
      final result = _generator.generate(
        _package([
          _module('Web', controllers: [_class('UsersController')]),
        ]),
      );

      expect(result.library, contains('controllers: [usersController()]'));
    });
  });

  group('structure', () {
    test('an id with quotes and dollars is escaped', () {
      final result = _generator.generate(
        _package([_module('Odd', id: "it's \$x\\")]),
      );

      expect(result.library, contains(r"id: 'it\'s \$x\\'"));
    });

    test('a cycle through three modules and a module importing itself', () {
      final result = _generator.generate(
        _package([
          _module('A', imports: [_local('B')]),
          _module('B', imports: [_local('C')]),
          _module('C', imports: [_local('A')]),
          _module('Self', imports: [_local('Self')]),
        ]),
      );

      expect(result.diagnostics.map((d) => d.message), [
        startsWith('Module imports form a cycle: A -> B -> C -> A.'),
        startsWith('Module imports form a cycle: Self -> Self.'),
      ]);
    });

    test('a duplicate id is reported on the second module and later', () {
      final result = _generator.generate(
        _package([
          _module('A', id: 'x'),
          _module('B', id: 'x'),
          _module('C', id: 'x'),
        ]),
      );

      expect(result.diagnostics.map((d) => d.location.line), [1, 1]);
      expect(result.diagnostics.map((d) => d.message), [
        startsWith('Modules A and B share'),
        startsWith('Modules A and C share'),
      ]);
    });

    test('exports of own providers, imports and tokens are valid', () {
      const token = ReferenceConstant(
        name: 'dbUrl',
        libraryUri: 'package:app/app.dart',
      );
      final key = _token(token);
      final result = _generator.generate(
        _package([
          _module('Base'),
          _module(
            'Rich',
            imports: [_local('Base')],
            providers: [ValueProvider(key, const StringConstant('x'))],
            exports: [KeyExport(key), ModuleReexport(_local('Base'))],
          ),
        ]),
      );

      expect(result.diagnostics, isEmpty);
      expect(
        result.library,
        contains('dartnest.Provider<String>.value(\'x\', token: i1.dbUrl)'),
      );
    });

    test('an unwritable token is reported once, however often it is used', () {
      const bad = UnsupportedConstant('_t is private');
      final key = _token(bad);
      final result = _generator.generate(
        _package([
          _module(
            'Bad',
            providers: [ValueProvider(key, const StringConstant('x'))],
            exports: [KeyExport(key)],
          ),
        ]),
      );

      expect(result.diagnostics.map((d) => d.message), [
        startsWith('Module "Bad": the token Token<String>(name) cannot'),
      ]);
    });
  });
}
