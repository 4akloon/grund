import '../di/errors.dart';

/// Errors raised while assembling or running an `Application`.
sealed class ApplicationError extends DartnestError {
  /// Creates an application error.
  const ApplicationError();
}

/// A controller factory threw.
final class ControllerCreationError extends ApplicationError {
  /// Creates the error.
  const ControllerCreationError({
    required this.controllerType,
    required this.moduleId,
    required this.error,
    required this.stackTrace,
  });

  /// The controller class.
  final Type controllerType;

  /// The module that declares the controller.
  final String moduleId;

  /// The original error.
  final Object error;

  /// The original stack trace.
  final StackTrace stackTrace;

  @override
  String get message =>
      'Factory of controller $controllerType in module "$moduleId" threw: '
      '$error';
}

/// An `Enhancers` list holds a component of the wrong kind, for example an
/// interceptor among the guards.
final class InvalidComponentError extends ApplicationError {
  /// Creates the error.
  const InvalidComponentError({
    required this.owner,
    required this.slot,
    required this.actualType,
    required this.expectedType,
  });

  /// Where the list is declared: `Application`, a controller type, or
  /// `Controller.handler`.
  final String owner;

  /// The list: `guards`, `interceptors`, `pipes` or `filters`.
  final String slot;

  /// Runtime type of the (resolved) component.
  final Type actualType;

  /// The kind the list requires.
  final Type expectedType;

  @override
  String get message =>
      '$owner lists $actualType in $slot, but it is not a $expectedType.';
}
