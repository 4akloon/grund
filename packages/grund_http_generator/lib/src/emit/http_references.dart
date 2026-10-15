import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';

/// How a generated `X.api.g.dart` names the declarations of
/// `package:grund_http`.
///
/// A part has no imports, so its names come from the host library; to be
/// independent of how the user imported the package (with `show`, or with
/// another prefix), the generated code always writes `http.Name`, and the
/// host must import the package with that prefix (`missing_required_import`
/// otherwise).
abstract final class HttpReferences {
  /// The library the generated code needs.
  static const importUri = 'package:grund_http/grund_http.dart';

  /// The prefix the host must import [importUri] with.
  static const importPrefix = 'http';

  /// The import directive the host must contain, as the diagnostics show it.
  static const importDirective = "import '$importUri' as $importPrefix;";

  /// [symbol] of `package:grund_http`, written with the prefix.
  static Reference of(String symbol) => refer('$importPrefix.$symbol');

  /// `HookRef<HttpHook>`.
  static TypeReference get hookRef => TypeReference(
    (b) => b
      ..symbol = '$importPrefix.HookRef'
      ..types.add(of('HttpHook')),
  );

  /// [value] with every declaration of `package:grund_http` renamed to its
  /// prefixed name, so a `HookRef` written in the annotation is written the
  /// same way as the rest of the generated code.
  static ConstantValue prefixed(ConstantValue value) => switch (value) {
    ObjectConstant() => ObjectConstant(
      type: _type(value.type),
      constructorName: value.constructorName,
      positional: [for (final v in value.positional) prefixed(v)],
      named: {
        for (final MapEntry(key: name, value: argument) in value.named.entries)
          name: prefixed(argument),
      },
    ),
    ReferenceConstant(:final libraryUri) when _isHttp(libraryUri) => _reference(
      value,
    ),
    ListConstant() => ListConstant(_type(value.elementType), [
      for (final element in value.elements) prefixed(element),
    ]),
    SetConstant() => SetConstant(_type(value.elementType), [
      for (final element in value.elements) prefixed(element),
    ]),
    MapConstant() => MapConstant(_type(value.keyType), _type(value.valueType), [
      for (final (k, v) in value.entries) (prefixed(k), prefixed(v)),
    ]),
    TypeConstant() => TypeConstant(_type(value.type)),
    _ => value,
  };

  // The prefix is part of the name and the library is a core one, so no
  // later step adds an import or another prefix: a part has no imports and
  // writes the reference exactly as given.
  static ReferenceConstant _reference(ReferenceConstant value) =>
      switch (value.enclosingName) {
        final enclosing? => ReferenceConstant(
          name: value.name,
          libraryUri: 'dart:core',
          enclosingName: '$importPrefix.$enclosing',
        ),
        null => ReferenceConstant(
          name: '$importPrefix.${value.name}',
          libraryUri: 'dart:core',
        ),
      };

  static TypeModel _type(TypeModel type) => TypeModel(
    name: _isHttp(type.libraryUri) ? '$importPrefix.${type.name}' : type.name,
    kind: type.kind,
    libraryUri: _isHttp(type.libraryUri) ? null : type.libraryUri,
    typeArguments: [for (final argument in type.typeArguments) _type(argument)],
    isNullable: type.isNullable,
  );

  static bool _isHttp(String? libraryUri) =>
      libraryUri != null && libraryUri.startsWith('package:grund_http/');
}
