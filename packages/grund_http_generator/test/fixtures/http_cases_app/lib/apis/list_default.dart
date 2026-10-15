// An API whose list query parameter has a default value.
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'list_default.g.dart';

/// Filters by tags.
@Api('/tags')
final class ListDefaultApi {
  /// Lists with a default tag.
  @Get('/')
  String list(http.HttpCtx c, {@Query() List<String> tag = const ['a']}) =>
      tag.join();
}
