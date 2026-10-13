import 'dart:async';

import 'argument_meta.dart';
import 'pipeline_component.dart';

/// Transforms or validates one handler argument.
///
/// Pipes run inside `ExecutionContext.param`, `query` and `bodyAs`, in the
/// order application → controller → route → the call's own `pipes`, on the
/// raw value: a `String` (or `null` when a query parameter is absent) for
/// parameters, the decoded JSON for the body. Built-in conversion to the
/// requested type runs after the pipes, and only when the value is not
/// already of that type. Throw `BadRequestException` to reject a value.
///
/// A pipe with a typed input must tolerate `null` for absent query
/// parameters, so declare `Pipe<String?, O>`.
///
/// Pipes listed in `Enhancers` see every argument, so they should implement
/// `Pipe<Object?, Object?>` and pass through values they do not handle.
abstract interface class Pipe<I, O> implements PipelineComponent {
  /// Transforms [value] of the argument described by [meta].
  FutureOr<O> transform(I value, ArgumentMeta meta);
}
