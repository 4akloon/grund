// An API with routes whose last parameter carries a literal suffix.
import 'package:grund_http/annotations.dart';
import 'package:grund_http/grund_http.dart' as http;

part 'suffix_route.g.dart';

/// Answers `/docs/:id.json`, `/docs/:id` and two more suffixed shapes.
@Api('/docs')
final class SuffixRouteApi {
  /// Creates the API.
  SuffixRouteApi();

  /// The JSON form of a document.
  @Get('/:id.json')
  String json(@Path() String id) => 'json $id';

  /// The plain form of a document.
  @Get('/:id')
  String plain(@Path() String id) => 'plain $id';

  /// A multi-dot suffix.
  @Get('/:name.tar.gz')
  String archive(@Path() String name) => 'archive $name';

  /// A suffix below a literal segment.
  @Get('/x/:id.md')
  String markdown(@Path() String id) => 'markdown $id';
}
