// An API whose routes the generator rejects, one problem per method.
import 'package:grund_http/annotations.dart';

import 'tasks.dart';

/// A class without `@Injectable` or `@Api`.
final class NoJson {}

/// Every route has a problem.
@Api('/bad', use: [42])
final class BadApi {
  /// Two annotations.
  @Get('/a')
  @Post('/a')
  void twice() {}

  /// Static.
  @Get('/b')
  static void staticHandler() {}

  /// A stream of non-bytes.
  @Get('/c')
  Stream<Task> events() => const Stream.empty();

  /// A parameter without a source.
  @Get('/d')
  void noSource(int page) {}

  /// A body without `fromJson`.
  @Post('/e')
  void body(@Body() NoJson dto) {}

  /// A path parameter the path does not have.
  @Get('/f/:id')
  void unknownPath(@Path() int other) {}

  /// Two sources.
  @Get('/g')
  void both(@Path() @Query() int x) {}

  /// A validator of the wrong type.
  @Get('/h')
  void range(@Query() @Range(min: 1) String name) {}

  /// A type no reader supports.
  @Get('/i')
  void number(@Query() num n) {}

  /// A function type result.
  @Get('/j')
  void Function() callback() => () {};

  /// Same method and path as the next one.
  @Get('/dup/:a')
  void one() {}

  /// Same method and path as the previous one.
  @Get('/dup/:b')
  void two() {}

  /// A hook that is not a HookRef.
  @Get('/k', use: ['hook'], status: 700)
  void hook() {}

  /// An optional named and an optional positional query parameter: valid.
  @Get('/l')
  Future<void> optional(@Query() int? a, [@Query() int b = 1]) async {}
}

/// Routes outside of an API.
final class NotAnApi {
  /// Never served.
  @Get('/stray')
  void stray() {}
}
