import 'dart:io';

import 'package:grund_generator/grund_generator.dart';
import 'package:grund_http_generator/src/model/http_package_model.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

/// The three ways to write a hook in `use:` (a class, a constant instance,
/// a `HookRef`) give the same generated code.
void main() {
  late FixturePackage fixture; // Set in setUpAll.

  setUpAll(() => fixture = FixturePackage.open('http_cases_app'));

  Future<GenerationResult> generate(String name) async => const GrundGenerator(
    FixturePackage.constructs,
  ).generate(await fixture.collect(['lib/apis/$name.dart']));

  /// The generated part of `hook_forms_<form>.dart`, with its own file name
  /// replaced so that two forms can be compared.
  Future<String> generated(String form) async {
    final result = await generate('hook_forms_$form');
    expect(result.diagnostics, isEmpty);
    return result.files['lib/apis/hook_forms_$form.g.dart']!.replaceAll(
      'hook_forms_$form',
      'hook_forms',
    );
  }

  for (final form in ['short', 'ref', 'mixed']) {
    test('hook_forms_$form generates the committed file', () async {
      final result = await generate('hook_forms_$form');

      expect(
        result.files['lib/apis/hook_forms_$form.g.dart'],
        File(
          '${fixture.root}/lib/apis/hook_forms_$form.g.dart',
        ).readAsStringSync(),
      );
    });
  }

  test('classes and instances give the bytes of the HookRef form', () async {
    expect(await generated('short'), await generated('ref'));
  });

  test('a mix of the three forms gives the same bytes too', () async {
    expect(await generated('mixed'), await generated('ref'));
  });

  test(
    'hooks keep their order, with the api hooks before the routes',
    () async {
      final source = await generated('short');

      expect(
        source,
        allOf(
          contains('http.HookRef<FormsAuthHook>.type()'),
          contains('http.HookRef<FormsAuditHook>.instance(FormsAuditHook())'),
          contains('http.HookRef<FormsRolesHook>.instance(FormsRolesHook(2))'),
        ),
      );
      expect(
        source.indexOf('HookRef<FormsAuthHook>.type()'),
        lessThan(source.indexOf('HookRef<FormsAuditHook>')),
      );
    },
  );

  test('the model tells a class from an instance', () async {
    final package = await fixture.collect(['lib/apis/hook_forms_short.dart']);
    final api = package.extensionModel<HttpPackageModel>()!.apis.single;

    expect(
      [for (final h in api.use) '${h.type.display} ${h.isInstance}'],
      ['FormsAuthHook false', 'FormsAuditHook true'],
    );
    expect(
      [
        for (final h in api.routes.single.use)
          '${h.type.display} ${h.isInstance}',
      ],
      ['FormsRolesHook true', 'FormsAuthHook false'],
    );
  });

  test(
    'an entry that is not a hook names itself and the three forms',
    () async {
      final result = await generate('invalid_hooks');
      final hooks = [
        for (final d in result.diagnostics)
          if (d.code.id == 'invalid_hook') d,
      ];

      expect(
        [for (final d in hooks) '${d.location}'],
        [
          'lib/apis/invalid_hooks.dart:8:13',
          'lib/apis/invalid_hooks.dart:11:10',
          'lib/apis/invalid_hooks.dart:15:10',
          'lib/apis/invalid_hooks.dart:19:10',
        ],
      );
      expect(hooks.first.message, contains('use: NotAHook is not a hook'));
      expect(hooks.first.message, contains('a hook class (`ApiKeyHook`)'));
      expect(hooks[1].message, contains('a value of type NotAHook'));
      expect(hooks[2].message, contains('a value of type String'));
      expect(hooks[3].message, contains('a value of type int'));
    },
  );

  test('a hook constant of a private class is reported as private', () async {
    final result = await generate('invalid_private_hook');
    final unsupported = [
      for (final d in result.diagnostics)
        if (d.code.id == 'unsupported_constant') d,
    ];

    expect(
      [for (final d in unsupported) d.message],
      [contains('_PrivHook is private')],
    );
  });

  /// `type isInstance` of each hook of `MoreHooksApi`.
  Future<List<String>> moreHooks() async {
    final package = await fixture.collect(['lib/apis/hook_forms_more.dart']);
    final api = package.extensionModel<HttpPackageModel>()!.apis.single;
    return [for (final h in api.use) '${h.type.display} ${h.isInstance}'];
  }

  test('a const variable is an instance of its type', () async {
    expect((await moreHooks())[0], 'FormsRolesHook true');
  });

  test('an alias of a hook class is the class itself', () async {
    expect((await moreHooks())[1], 'FormsAuthHook false');
  });

  test('a generic hook class keeps its type arguments', () async {
    expect((await moreHooks())[2], 'FormsBoxHook<int> false');
  });

  test('a HookRef constant is an instance only through .instance', () async {
    final package = await fixture.collect(['lib/apis/hook_forms_ref.dart']);
    final api = package.extensionModel<HttpPackageModel>()!.apis.single;

    expect(
      [for (final h in api.use) '${h.type.display} ${h.isInstance}'],
      ['FormsAuthHook false', 'FormsAuditHook true'],
    );
  });
}
