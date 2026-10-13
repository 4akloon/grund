// Handlers and components the generator rejects.
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'components.dart';

/// No fromJson.
final class Opaque {
  /// The value.
  final int value = 0;
}

/// Every handler is wrong.
@Controller('/broken')
@UseGuards([PassInterceptor, String])
final class BrokenController {
  /// Unbound parameter.
  @Get('/a')
  int unbound(int value) => value;

  /// Two binding annotations.
  @Get('/b/:id')
  int twice(@Param('id') @Query('id') int id) => id;

  /// A list query.
  @Get('/c')
  int list(@Query('tags') List<String> tags) => tags.length;

  /// An int header.
  @Get('/d')
  int header(@Header('x-count') int count) => count;

  /// A body without fromJson.
  @Post('/e')
  int body(@Body() Opaque opaque) => opaque.value;

  /// Two routes.
  @Get('/f')
  @Post('/f')
  void twoRoutes() {}

  /// Static.
  @Get('/g')
  static void notInstance() {}

  /// Generic.
  @Get('/h')
  T generic<T>() => throw UnimplementedError();

  /// A path parameter the path does not declare.
  @Get('/i/:id')
  String unknown(@Param('slug') String slug) => slug;

  /// The first of two routes with one shape.
  @Get('/j/:a')
  void first() {}

  /// The second of two routes with one shape.
  @Get('/j/:b')
  void second() {}
}
