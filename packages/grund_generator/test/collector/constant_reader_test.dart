import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/src/collector/constant_reader.dart';
import 'package:grund_generator/src/collector/source_locations.dart';
import 'package:grund_generator/src/collector/token_reader.dart';
import 'package:grund_generator/src/model/constant_value.dart';
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

  group('edge constants', () {
    late LibraryElement edges; // Set in setUpAll.

    setUpAll(() async {
      edges = (await fixture.libraries(['lib/edge_constants.dart'])).single;
    });

    ConstantValue probe(String className) {
      final element = edges.classes.firstWhere((c) => c.name == className);
      final annotation = element.metadata.annotations.single
          .computeConstantValue();
      final object = ConstantReader.read(annotation) as ObjectConstant;
      return object.positional.single;
    }

    test('null', () => expect(probe('NullCase'), isA<NullConstant>()));

    test('a bool', () {
      expect((probe('BoolCase') as BoolConstant).value, isTrue);
    });

    test('a double keeps its literal', () {
      expect((probe('DoubleCase') as NumberConstant).literal, '1.5');
    });

    test('a non-finite double is unsupported', () {
      expect(
        (probe('InfiniteCase') as UnsupportedConstant).reason,
        'Infinity is not a finite number',
      );
    });

    test('a private constructor is unsupported', () {
      expect(
        (probe('LockedCase') as UnsupportedConstant).reason,
        contains('constructor'),
      );
      expect(probe('LockedCase').unsupported?.reason, contains('private'));
    });

    test('a function is not a constructor call', () {
      expect(
        (probe('FunctionCase') as UnsupportedConstant).reason,
        contains('is not a constructor call'),
      );
    });

    test('a static constant of a public class is a reference', () {
      final reference = probe('StaticCase') as ReferenceConstant;

      expect('${reference.enclosingName}.${reference.name}', 'Limits.max');
      expect(reference.libraryUri, 'package:cases_app/edge_constants.dart');
    });

    test('a static constant of a private class is its value', () {
      expect((probe('PrivateOwnerCase') as NumberConstant).literal, '7');
    });
  });
}
