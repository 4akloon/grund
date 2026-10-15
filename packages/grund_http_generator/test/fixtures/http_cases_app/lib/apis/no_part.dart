// An API in a library with the prefixed import but without the part.
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

/// Answers pings.
@Api('/ping')
final class NoPartApi {
  /// Pong.
  @Get('/')
  String ping(http.HttpCtx c) => 'pong';
}
