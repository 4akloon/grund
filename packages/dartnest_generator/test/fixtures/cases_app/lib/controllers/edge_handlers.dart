// Corner cases of body kinds, scalar bindings and data classes.
import 'dart:async';

import 'package:dartnest/dartnest.dart' hide Controller, Module;
import 'package:dartnest_annotations/dartnest_annotations.dart';

import 'components.dart';
import 'users.dart';

/// A static `fromJson`.
final class StaticFrom {
  const StaticFrom._();

  /// Reads the body.
  static StaticFrom fromJson(Map<String, Object?> json) => const StaticFrom._();
}

/// An instance `fromJson`.
final class InstanceFrom {
  /// Not a factory.
  InstanceFrom fromJson(Map<String, Object?> json) => this;
}

/// A `fromJson` with a second required parameter.
final class TwoArgs {
  /// Needs more than the map.
  const TwoArgs.fromJson(Map<String, Object?> json, int extra);
}

/// A `fromJson` with a named parameter.
final class NamedArg {
  /// Takes the map by name.
  const NamedArg.fromJson({required Map<String, Object?> json});
}

/// A `fromJson` of the wrong type.
final class WrongParam {
  /// Takes text.
  const WrongParam.fromJson(String text);
}

/// A map with the wrong value type.
final class WrongMap {
  /// Takes `Map<String, int>`.
  const WrongMap.fromJson(Map<String, int> json);
}

/// A generic class.
final class Box<T> {
  /// Reads the body.
  const Box.fromJson(Map<String, Object?> json);
}

/// A tree node, which refers to itself.
final class Node {
  /// Creates a node.
  const Node(this.next, {this.label = 'n'});

  /// The next node.
  final Node? next;

  /// The label.
  @JsonKey()
  final String label;

  /// Another annotation, which is not a `JsonKey`.
  @Deprecated('Kept to test other annotations.')
  final int legacy = 0;

  /// Not a field of the JSON.
  static int counter = 0;

  /// Derived.
  int get total => 1;
}

/// Reached only through a map, which is not followed.
final class Hidden {
  /// The value.
  final int value = 0;
}

/// Without an unnamed constructor.
final class Sealed {
  const Sealed._(this.value);

  /// The value.
  final int value;
}

/// Edge cases.
@Controller()
@UseGuards([OpenGuard])
@UseGuards([dynamic])
final class EdgeController {
  /// A nullable body.
  @Post('/a')
  void nullableBody(@Body() CreateUser? body) {}

  /// A list of strings.
  @Post('/b')
  void strings(@Body() List<String> body) {}

  /// A `dynamic` map.
  @Post('/c')
  void dynamicMap(@Body() Map<String, dynamic> body) {}

  /// A map with int keys.
  @Post('/d')
  void intKeys(@Body() Map<int, Object?> body) {}

  /// Static, instance and bad `fromJson`.
  @Post('/e')
  void bodies(
    @Body() StaticFrom staticFrom,
    @Body() InstanceFrom instanceFrom,
    @Body() TwoArgs twoArgs,
    @Body() NamedArg namedArg,
    @Body() WrongParam wrongParam,
  ) {}

  /// More bad bodies.
  @Post('/f')
  void moreBodies(
    @Body() WrongMap wrongMap,
    @Body() Box<int> box,
    @Body() void Function() function,
  ) {}

  /// A list as a path parameter.
  @Get('/g')
  void pathList(@Param('id') List<int> id) {}

  /// Valid scalars.
  @Get('/h/:when')
  void scalars(
    @Param('when') DateTime when,
    @Query('ratio') double? ratio,
    @Header('x-id') String id,
    @Query('flag') bool flag,
    @Query('n') num n,
  ) {}

  /// A named parameter.
  @Get('/i')
  void named({@Query('q') required String q}) {}

  /// A private handler.
  @Get('/p')
  // ignore: unused_element, a private handler is what this case checks
  void _hidden() {}

  /// Wrapped results.
  @Get('/j')
  Future<Set<Node>> nodes() async => const {};

  /// Results that are not data classes.
  @Get('/k')
  FutureOr<Map<String, Hidden>> notData(ExecutionContext context) => const {};

  /// An enum and a class without an unnamed constructor.
  @Get('/l')
  Future<List<Sealed>> sealed(@Query('status') Status status) async => const [];

  /// A `void` and a `dynamic` result.
  @Get('/m')
  dynamic anything() {}
}
