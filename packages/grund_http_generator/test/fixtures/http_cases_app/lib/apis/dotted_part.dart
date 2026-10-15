// A library whose part directive is written with a redundant `./`.
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part './dotted_part.g.dart';

/// Answers pings.
@Api('/dotted')
final class DottedPartApi {
  /// Pong.
  @Get('/')
  String ping(http.HttpCtx c) => 'pong';
}
