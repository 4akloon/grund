import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartnest_generator/src/collector/constant_reader.dart';
import 'package:dartnest_generator/src/collector/source_locations.dart';
import 'package:dartnest_generator/src/collector/token_reader.dart';
import 'package:dartnest_generator/src/model/constant_value.dart';
import 'package:test/test.dart';

import '../helpers/fixture_package.dart';

void main() {
  late FixturePackage fixture; // Set in setUpAll.
  late ClassElement holder; // Set in setUpAll.

  setUpAll(() async {
    fixture = FixturePackage.open('cases_app');
    final library = (await fixture.libraries(['lib/constants.dart'])).single;
    holder = library.classes.firstWhere((c) => c.name == 'Holder');
  });

  DartObject annotation(String name) => [
    for (final a in holder.metadata.annotations)
      if (a.computeConstantValue() case final value?) value,
  ].firstWhere((value) => value.type?.element?.name == name);

  test('an object constant keeps its constructor arguments', () {
    final tagged = ConstantReader.read(annotation('Tagged')) as ObjectConstant;

    expect(tagged.type.display, 'Tagged');
    expect(tagged.constructorName, '');
    expect((tagged.positional.single as StringConstant).value, r"it's $5");
    expect((tagged.named['count'] as NumberConstant).literal, '3');
    expect(
      (tagged.named['flags'] as SetConstant).elements.single,
      isA<StringConstant>(),
    );
    final extra = tagged.named['extra'] as MapConstant;
    expect('${extra.keyType} ${extra.valueType}', 'String int');
    final status = tagged.named['status'] as ReferenceConstant;
    expect('${status.enclosingName}.${status.name}', 'Status.banned');
    expect((tagged.named['type'] as TypeConstant).type.display, 'Holder');
    expect(tagged.unsupported, isNull);
  });

  test('a public constant is read as a reference to it', () {
    final inject = ConstantReader.read(annotation('Inject')) as ObjectConstant;
    final token = inject.positional.single as ReferenceConstant;

    expect(token.name, 'dbUrl');
    expect(token.libraryUri, 'package:cases_app/constants.dart');
    expect(token.enclosingName, isNull);
  });

  // Review Focus 3: private constants and classes in annotations.
  test('a private constant is rebuilt from its constructor call', () {
    final value = ConstantReader.read(annotation('Value')) as ObjectConstant;
    final token = value.positional.single as ObjectConstant;

    expect(token.type.display, 'Token<int>');
    expect((token.positional.single as StringConstant).value, 'secret');
  });

  // Review Focus 3.
  test('a private class cannot be written in generated code', () {
    final wrapped = ConstantReader.read(annotation('Wrapped'));

    expect(wrapped.unsupported?.reason, '_Hidden is private');
  });

  test('a list of types', () {
    final guards = ConstantReader.read(annotation('UseGuards'));
    final types = (guards as ObjectConstant).positional.single as ListConstant;

    expect(types.elementType.display, 'Type');
    expect((types.elements.single as TypeConstant).type.display, 'Holder');
  });

  test('a token reads as a key with its value type', () {
    final inject = annotation('Inject');
    final (key, valueType) =
        TokenReader.read(inject.getField('token')) ?? fail('not a token');

    expect(key.display, 'Token<String>(db.url)');
    expect(valueType.isDartCoreString, isTrue);
    expect(key.expression, isA<ReferenceConstant>());
    expect(TokenReader.read(annotation('Tagged')), isNull);
  });

  test('locations are relative to the package root', () {
    final location = SourceLocations(fixture.root).of(holder);
    final source = fixture.read('lib/constants.dart').split('\n');

    expect(location.path, 'lib/constants.dart');
    expect(source[location.line - 1].indexOf('Holder'), location.column - 1);
  });
}
