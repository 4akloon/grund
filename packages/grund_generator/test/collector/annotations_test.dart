import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/src/collector/annotations.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late ClassElement holder; // Set in setUpAll.

  setUpAll(() async {
    final fixture = FixturePackage.open('cases_app');
    final library = (await fixture.libraries(['lib/constants.dart'])).single;
    holder = library.classes.firstWhere((c) => c.name == 'Holder');
  });

  String? typeName(DartObject? value) => value?.type?.element?.name;

  test('find returns the first annotation of that name', () {
    expect(typeName(Annotations.find(holder, 'Api')), 'Api');
    expect(Annotations.find(holder, 'Module'), isNull);
  });

  test('all returns annotations of any given name in source order', () {
    final found = Annotations.all(holder, {'Api', 'Named'});

    expect(found.map(typeName), ['Named', 'Api']);
  });

  test('an annotation from another package is not matched by name', () {
    expect(Annotations.all(holder, {'Tagged', 'Wrapped'}), isEmpty);
  });

  test('named reads the name of @Named', () {
    expect(Annotations.named(holder), 'db');
  });

  test('field reads a field declared on the annotation class', () {
    final api = Annotations.find(holder, 'Api')!;

    expect(Annotations.field(api, 'path')?.toStringValue(), '/holder');
    expect(Annotations.field(api, 'missing'), isNull);
  });

  test('describe names a type and falls back to the value type', () {
    final api = Annotations.find(holder, 'Api')!;
    final use = Annotations.field(api, 'use')?.toListValue();

    expect(Annotations.describe(use!.single), 'a value of type Symbol');
    expect(Annotations.describe(api), 'a value of type Api');
  });
}
