import 'package:code_builder/code_builder.dart';
import 'package:grund_generator/grund_generator.dart';

import '../model/body_kind.dart';
import '../model/param_model.dart';
import '../model/param_source.dart';
import '../model/validator_model.dart';
import '../model/value_kind.dart';
import 'http_references.dart';

/// Writes the expression that produces one argument of a route handler from
/// the `HttpCtx` named `c`: a `Params` reader call, the request body, the
/// context itself or a value of the call scope.
abstract final class ParamEmitter {
  /// The argument expression of [param]; it contains `await` exactly when
  /// [awaits] is true.
  static Expression argument(ParamModel param) => switch (param.source) {
    final ValueSource source => _value(param, source),
    BodySource(:final kind) => _body(param, kind),
    ContextSource() => refer('c'),
    CallScopeSource(:final key) => refer('c').call(
      [if (key.name case final name?) DartString.expression(name)],
      const {},
      [TypeEmitter.reference(key.type)],
    ),
    InvalidSource(:final problem) => throw StateError(
      'An invalid parameter reached generation: $problem',
    ),
  };

  /// Whether [argument] of [param] awaits the body of the request.
  static bool awaits(ParamModel param) => param.source is BodySource;

  static Expression _value(ParamModel param, ValueSource source) {
    final kind = source.kind;
    final reader = refer('c').property(source.location.reader);
    if (kind == ValueKind.stringList) {
      return reader.property('all').call([DartString.expression(source.name)]);
    }
    final optional = param.type.isNullable || param.defaultValue != null;
    final method = '${kind.reader}${optional ? 'OrNull' : ''}';
    final call = reader.property(method).call([
      DartString.expression(source.name),
      if (kind == ValueKind.enumeration)
        TypeEmitter.reference(param.type.nonNullable).property('values'),
    ], _constraints(param.validators));
    return switch (param.defaultValue) {
      final fallback? => call.ifNullThen(
        ConstantEmitter.expression(HttpReferences.prefixed(fallback)),
      ),
      null => call,
    };
  }

  static Map<String, Expression> _constraints(List<ValidatorModel> validators) {
    final named = <String, Expression>{};
    for (final validator in validators) {
      switch (validator) {
        case RangeValidator(:final min, :final max):
          if (min != null) named['min'] = literalNum(min);
          if (max != null) named['max'] = literalNum(max);
        case LengthValidator(:final min, :final max):
          if (min != null) named['minLength'] = literalNum(min);
          if (max != null) named['maxLength'] = literalNum(max);
        case PatternValidator(:final regex):
          named['pattern'] = DartString.expression(regex);
        case OneOfValidator(:final values):
          named['oneOf'] = literalConstList([
            for (final value in values) DartString.expression(value),
          ]);
      }
    }
    return named;
  }

  static Expression _body(ParamModel param, BodyKind kind) {
    final c = refer('c');
    final type = param.type;
    return switch (kind) {
      BodyKind.object => c.property('body').call([
        TypeEmitter.reference(type).property('fromJson'),
      ]).awaited,
      BodyKind.list => c.property('bodyList').call([
        TypeEmitter.reference(type.typeArguments.single).property('fromJson'),
      ]).awaited,
      BodyKind.jsonObject => c.property('body').call([
        Method(
          (b) => b
            ..requiredParameters.add(Parameter((p) => p..name = 'json'))
            ..lambda = true
            ..body = const Code('json'),
        ).closure,
      ]).awaited,
      BodyKind.bytes => c.property('bytes').call(const []).awaited,
      BodyKind.unsupported => throw StateError(
        'An unsupported body reached generation: ${param.name}.',
      ),
    };
  }
}
