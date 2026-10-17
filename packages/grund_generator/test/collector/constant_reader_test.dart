import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/src/collector/constant_reader.dart';
import 'package:grund_generator/src/collector/source_locations.dart';
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

  List<DartObject> wrappedValues() => [
    for (final a in holder.metadata.annotations)
      if (a.computeConstantValue() case final value?)
        if (value.type?.element?.name == 'Wrapped') value,
  ];

  ConstantValue wrapped(int index) => (ConstantReader.read(
    wrappedValues()[index],
  ) as ObjectConstant).positional.single;

  // Review Focus 3: private constants and classes in annotations.
  test('a private constant is rebuilt from its constructor call', () {
    final label = wrapped(1) as ObjectConstant;

    expect(label.type.display, 'Label');
    expect((label.positional.single as StringConstant).value, 'secret');
  });

  test('a private class cannot be written in generated code', () {
    final hidden = ConstantReader.read(wrappedValues().first);

    expect(hidden.unsupported?.reason, '_Hidden is private');
  });

  test('a named constructor keeps its name and type arguments', () {
    final ref = wrapped(2) as ObjectConstant;

    expect(ref.type.display, 'Ref<Holder>');
    expect(ref.constructorName, 'instance');
    expect(ref.positional.single, isA<ObjectConstant>());
  });

  test('a key keeps its name argument', () {
    final key = wrapped(3) as ObjectConstant;

    expect(key.type.display, 'Key<Holder>');
    expect((key.positional.single as StringConstant).value, 'main');
  });

  test('a list of symbols is unsupported', () {
    final module = ConstantReader.read(annotation('Module')) as ObjectConstant;
    final imports = module.named['imports'] as ListConstant;

    expect(imports.elements.single, isA<UnsupportedConstant>());
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
