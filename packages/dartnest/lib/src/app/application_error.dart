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
