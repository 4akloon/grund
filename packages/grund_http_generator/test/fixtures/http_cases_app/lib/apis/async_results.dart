// An API whose handlers declare FutureOr results.
import 'dart:async';

import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'async_results.g.dart';

/// Records what the handlers did, in order.
final class AsyncLog {
  /// The recorded steps.
  final List<String> steps = [];
}

/// Handlers that declare `FutureOr` instead of `Future`.
@Api('/async')
final class AsyncResultsApi {
  /// Creates the API.
  AsyncResultsApi(this.log);

  /// Where the handlers record their steps.
  final AsyncLog log;

  /// Works after an await and then finishes.
  @Delete('/:id')
  FutureOr<void> remove(@Path() int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    log.steps.add('removed $id');
  }

  /// Fails after an await.
  @Post('/boom')
  FutureOr<void> boom() async {
    await Future<void>.delayed(Duration.zero);
    throw StateError('boom');
  }

  /// Returns a value that is a future.
  @Get('/:id')
  FutureOr<String> find(@Path() int id) async {
    await Future<void>.delayed(Duration.zero);
    return 'item $id';
  }
}
