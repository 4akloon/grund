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
    expect(typeName(Annotations.core.find(holder, 'Module')), 'Module');
    expect(Annotations.core.find(holder, 'Injectable'), isNull);
  });

  test('all returns annotations of any given name in source order', () {
    final found = Annotations.core.all(holder, {'Module', 'Named'});

    expect(found.map(typeName), ['Named', 'Module']);
  });

  test('an annotation from another package is not matched by name', () {
    expect(Annotations.core.all(holder, {'Tagged', 'Wrapped'}), isEmpty);
  });

  test('a class of that name from an unlisted library is not matched', () {
    const other = Annotations({'package:other/src/'});

    expect(other.find(holder, 'Module'), isNull);
    expect(other.named(holder), isNull);
  });

  test('named reads the name of @Named', () {
    expect(Annotations.core.named(holder), 'db');
  });

  test('field reads a field declared on the annotation class', () {
    final named = Annotations.core.find(holder, 'Named')!;

    expect(Annotations.field(named, 'name')?.toStringValue(), 'db');
    expect(Annotations.field(named, 'missing'), isNull);
  });

  test('describe names a type and falls back to the value type', () {
    final module = Annotations.core.find(holder, 'Module')!;
    final imports = Annotations.field(module, 'imports')?.toListValue();

    expect(Annotations.describe(imports!.single), 'a value of type Symbol');
    expect(Annotations.describe(module), 'a value of type Module');
  });
}
