// An API in a library without the part directive and with the package
// imported without the prefix the generated routes use.
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart';

/// Answers pings.
@Api('/ping')
final class PingApi {
  /// Pong.
  @Get('/')
  String ping(HttpCtx c) => 'pong';
}
