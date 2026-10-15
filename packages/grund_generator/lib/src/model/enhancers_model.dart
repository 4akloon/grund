import 'component_reference.dart';

/// The `@Use...` components of a controller or a route.
final class EnhancersModel {
  /// Creates the model; every list defaults to empty.
  const EnhancersModel({
    this.guards = const [],
    this.interceptors = const [],
    this.pipes = const [],
    this.filters = const [],
  });

  /// From `@UseGuards`.
  final List<ComponentReference> guards;

  /// From `@UseInterceptors`.
  final List<ComponentReference> interceptors;

  /// From `@UsePipes`.
  final List<ComponentReference> pipes;

  /// From `@UseFilters`.
  final List<ComponentReference> filters;

  /// Every component, guards first.
  List<ComponentReference> get all => [
    ...guards,
    ...interceptors,
    ...pipes,
    ...filters,
  ];
}
