import 'package:grund_generator/src/construct/grund_generator.dart';
import 'package:grund_generator/src/constructs/module_construct.dart';
import 'package:grund_generator/src/constructs/provider_construct.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('cases_app'));

  test(
    'constructors and parameters injection cannot use, provided or not',
    () async {
      final package = await fixture.collect([
        'lib/providers/provider_module.dart',
        'lib/providers/constructors.dart',
        'lib/modules/basic.dart',
      ]);

      expect(const ProviderConstruct().validate(package).map((d) => '$d'), [
        'lib/providers/constructors.dart:8:13: error: Plain is a provider of '
            'module "ProvidersModule" but is not annotated with @Injectable(). '
            '[not_injectable]',
        'lib/providers/constructors.dart:12:16: error: Shape is abstract. '
            '[invalid_constructor]',
        'lib/providers/constructors.dart:29:18: error: Parameter clock of '
            'Optional is optional; grund injects required positional and '
            'required named parameters only. [invalid_dependency]',
        'lib/providers/constructors.dart:76:33: error: Parameter port of '
            'BadTokens has type int, but Token<String>(db.url) provides String. '
            '[invalid_dependency]',
        'lib/providers/constructors.dart:76:62: error: The @Inject argument of '
            'Parameter url of BadTokens is not a Token. [invalid_dependency]',
        'lib/providers/provider_module.dart:16:36: error: The token of '
            'parameter port of PrivateToken cannot be written in generated '
            'code: _Port is private. Use a public constant token. '
            '[unsupported_constant]',
        'lib/providers/constructors.dart:16:13: error: Box is generic; provide '
            'a subclass with fixed type arguments. [invalid_constructor]',
        'lib/providers/constructors.dart:20:13: error: Named has no unnamed '
            'constructor; grund creates it with Named(...). '
            '[invalid_constructor]',
        'lib/providers/constructors.dart:39:12: error: Parameter clock of Odd '
            'has type Clock?; grund injects non-nullable class types, or a '
            'Token with @Inject(token). [invalid_dependency]',
        'lib/providers/constructors.dart:39:24: error: Parameter callback of '
            'Odd has type void Function(); grund injects non-nullable class '
            'types, or a Token with @Inject(token). [invalid_dependency]',
        'lib/providers/constructors.dart:51:13: error: _Hidden is private. '
            '[invalid_constructor]',
        'lib/providers/constructors.dart:66:14: error: Parameter anything of '
            'Loose has type Object; grund injects non-nullable class types, '
            'or a Token with @Inject(token). [invalid_dependency]',
      ]);
    },
  );

  test('one private factory per provided class, in module order', () async {
    final result = const GrundGenerator([
      ModuleConstruct(),
      ProviderConstruct(),
    ]).generate(await fixture.collect(['lib/modules/basic.dart']));

    expect(
      result.library,
      endsWith('''
i1.Repo _createRepo(grund.Injector i) =>
    i1.Repo(i.get<i1.Clock>(), i.get(i1.dbUrl), config: i.get<i1.AppConfig>());

i1.SystemClock _createSystemClock(grund.Injector i) => i1.SystemClock();
'''),
    );
  });
}
