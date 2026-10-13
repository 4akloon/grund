import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartnest_generator/src/collector/annotations.dart';
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
    expect(typeName(Annotations.find(holder, 'Inject')), 'Inject');
    expect(Annotations.find(holder, 'Module'), isNull);
  });

  test('all returns annotations of any given name in source order', () {
    final found = Annotations.all(holder, {'UseGuards', 'Inject'});

    expect(found.map(typeName), ['Inject', 'UseGuards']);
  });

  test('an annotation from another package is not matched by name', () {
    expect(Annotations.all(holder, {'Tagged', 'Wrapped'}), isEmpty);
  });

  test('routeMetadata returns annotations extending RouteMetadata', () {
    final found = Annotations.routeMetadata(holder);

    expect(found.map(typeName), ['Tagged', 'Wrapped']);
  });

  test('field reads a field declared on the annotation class', () {
    final tagged = Annotations.routeMetadata(holder).first;

    expect(Annotations.field(tagged, 'label')?.toStringValue(), r"it's $5");
    expect(Annotations.field(tagged, 'missing'), isNull);
  });

  test('field looks through the super chain', () {
    final guards = Annotations.find(holder, 'UseGuards')!;

    // `types` is declared on the superclass UseComponents.
    expect(guards.getField('types'), isNull);
    expect(Annotations.field(guards, 'types')?.toListValue(), hasLength(1));
  });

  test('describe names a type and falls back to the value type', () {
    final guards = Annotations.find(holder, 'UseGuards')!;
    final types = Annotations.field(guards, 'types')?.toListValue();
    final tagged = Annotations.routeMetadata(holder).first;

    expect(Annotations.describe(types!.single), 'Holder');
    expect(Annotations.describe(tagged), 'a value of type Tagged');
  });
}
