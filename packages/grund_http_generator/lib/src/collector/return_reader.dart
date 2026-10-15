import 'package:analyzer/dart/element/type.dart';

import '../model/return_kind.dart';

/// Classifies the return type of a route handler.
abstract final class ReturnReader {
  /// The kind of [returned], looking through one `Future` or `FutureOr`.
  static ReturnKind read(DartType returned) {
    final type = _unwrapped(returned);
    if (type is VoidType || type.isDartCoreNull) return ReturnKind.none;
    if (type is InterfaceType && type.isDartAsyncStream) {
      return _isByteList(type.typeArguments.single)
          ? ReturnKind.byteStream
          : ReturnKind.stream;
    }
    return type is InterfaceType || type is DynamicType
        ? ReturnKind.value
        : ReturnKind.unsupported;
  }

  static DartType _unwrapped(DartType type) =>
      type is InterfaceType &&
          (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
          type.typeArguments.length == 1
      ? type.typeArguments.single
      : type;

  static bool _isByteList(DartType type) =>
      type is InterfaceType &&
      type.isDartCoreList &&
      type.typeArguments.single.isDartCoreInt;
}
