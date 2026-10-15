import '../diagnostic/source_location.dart';
import 'hook_model.dart';
import 'param_model.dart';
import 'return_kind.dart';
import 'type_model.dart';

/// A method of an `@Api` class annotated with `@Get`, `@Post`, `@Put`,
/// `@Patch` or `@Delete`.
final class RouteModel {
  /// Creates the model.
  const RouteModel({
    required this.method,
    required this.path,
    required this.handlerName,
    required this.returnType,
    required this.returnKind,
    required this.location,
    this.status,
    this.parameters = const [],
    this.use = const [],
    this.invalidEntries = const [],
    this.documentation,
    this.problem,
  });

  /// The upper-cased HTTP method.
  final String method;

  /// The path relative to the API path.
  final String path;

  /// The method name.
  final String handlerName;

  /// The declared return type.
  final TypeModel returnType;

  /// What the handler returns.
  final ReturnKind returnKind;

  /// Where the method is declared.
  final SourceLocation location;

  /// The response status of the annotation, or `null`.
  final int? status;

  /// The parameters, in declaration order.
  final List<ParamModel> parameters;

  /// Route-level hooks, in order.
  final List<HookModel> use;

  /// One sentence per `use` entry the generator cannot use.
  final List<String> invalidEntries;

  /// The `///` comment of the method, if any.
  final String? documentation;

  /// Why the method cannot be a handler, as a sentence; `null` when it can.
  final String? problem;

  /// Names of the `:name` parameters and the `*` wildcard of [path].
  List<String> get pathParameters => [
    for (final segment in path.split('/'))
      if (segment.startsWith(':'))
        segment.substring(1)
      else if (segment == '*')
        '*',
  ];
}
