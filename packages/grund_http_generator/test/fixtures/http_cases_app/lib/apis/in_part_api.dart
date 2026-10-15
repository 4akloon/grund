// The @Api class of in_part.dart.
part of 'in_part.dart';

/// Answers pings.
@Api('/in-part')
final class InPartApi {
  /// Pong.
  @Get('/')
  String ping(http.HttpCtx c) => 'pong';
}
