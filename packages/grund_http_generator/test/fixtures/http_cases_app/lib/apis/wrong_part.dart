// A library whose part directive names a same-named file elsewhere.
import 'package:grund_annotations/grund_annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part '../other/wrong_part_api.g.dart';

/// Answers pings.
@Api('/wrong')
final class WrongPartApi {
  /// Pong.
  @Get('/')
  String ping(http.HttpCtx c) => 'pong';
}
