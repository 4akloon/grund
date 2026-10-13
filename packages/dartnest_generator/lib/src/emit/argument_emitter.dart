import 'package:code_builder/code_builder.dart';

import '../model/body_kind.dart';
import '../model/handler_parameter.dart';
import '../model/parameter_binding.dart';
import '../model/type_kind.dart';
import '../model/type_model.dart';
import 'dart_string.dart';
import 'import_allocator.dart';
import 'type_emitter.dart';

/// Writes the expression that fills one handler parameter from the
/// `ExecutionContext` named `ctx`.
abstract final class ArgumentEmitter {
  static final _context = refer('ctx');

  /// The argument for [parameter]; an `await` expression for path, query
  /// and body bindings.
  static Expression argument(HandlerParameter parameter) =>
      switch (parameter.binding) {
        PathBinding(:final name) => _converted('param', name, parameter.type),
        QueryBinding(:final name) => _converted('query', name, parameter.type),
        HeaderBinding(:final name) => _header(name, parameter.type),
        BodyBinding(:final kind) => _body(kind, parameter.type),
        ContextBinding() => _context,
        RequestBinding() =>
          _context.property('switchToHttp').call(const []).property('request'),
        InvalidBinding(:final problem) => throw StateError(
          'An invalid parameter reached generation: $problem',
        ),
      };

  /// Whether the argument for [parameter] awaits.
  static bool awaits(HandlerParameter parameter) => switch (parameter.binding) {
    PathBinding() || QueryBinding() || BodyBinding() => true,
    _ => false,
  };

  static Expression _converted(String method, String name, TypeModel type) =>
      _context.property(method).call(
        [_string(name)],
        {
          if (type.kind == TypeKind.enumeration)
            'pipes': literalConstList([
              refer('EnumPipe', ImportAllocator.dartnest).call([
                TypeEmitter.reference(type.nonNullable).property('values'),
              ]),
            ]),
        },
        [TypeEmitter.reference(type)],
      ).awaited;

  static Expression _header(String name, TypeModel type) {
    final header = _context.property('header').call([_string(name)]);
    if (type.isNullable) return header;
    final missing = refer('BadRequestException', ImportAllocator.dartnest)
        .constInstance(const [], {
          'message': _string('Missing header "$name".'),
        })
        .thrown
        .parenthesized;
    return header.ifNullThen(missing);
  }

  static Expression _body(BodyKind kind, TypeModel type) => switch (kind) {
    BodyKind.fromJson => _context.property('bodyAs').call([
      TypeEmitter.reference(type).property('fromJson'),
    ]),
    BodyKind.jsonObject =>
      _context
          .property('bodyAs')
          .call(
            [
              Method(
                (b) => b
                  ..requiredParameters.add(Parameter((p) => p..name = 'json'))
                  ..lambda = true
                  ..body = refer('json').code,
              ).closure,
            ],
            const {},
            [TypeEmitter.reference(type)],
          ),
    BodyKind.text => _context.property('body').property('text').call(const []),
    BodyKind.bytes =>
      _context.property('body').property('bytes').call(const []),
    BodyKind.unsupported => throw StateError(
      'A body without fromJson reached generation.',
    ),
  }.awaited;

  static Expression _string(String value) =>
      CodeExpression(Code(DartString.literal(value)));
}
