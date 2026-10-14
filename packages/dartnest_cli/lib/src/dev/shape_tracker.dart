import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Remembers the shape of Dart files: the declarations a hot reload cannot
/// apply to state that already exists.
///
/// The shape of a file is the source (without comments and formatting) of
/// its top-level variables, fields, constructors and enum values. A
/// changed field or constructor would leave instances created before the
/// reload (the providers kept by `Container.reassemble`) with fields that
/// were never initialized; a changed initializer of a top-level or static
/// variable, or a changed `const`, is not applied by a reload at all. A
/// change of anything else (method bodies, functions, annotations of
/// classes and methods) is reloadable.
final class ShapeTracker {
  final _shapes = <String, String>{};

  /// The shape of the Dart [source]; syntax errors are tolerated.
  static String shapeOf(String source) {
    final collector = _ShapeCollector();
    parseString(
      content: source,
      throwIfDiagnostics: false,
    ).unit.accept(collector);
    return collector.parts.join('\n');
  }

  /// Remembers the shapes of the files at [paths]; missing files are
  /// skipped.
  void remember(Iterable<String> paths) {
    for (final path in paths) {
      final source = _read(path);
      if (source != null) _shapes[path] = shapeOf(source);
    }
  }

  /// The [paths] whose shape differs from the one remembered, in the
  /// order given; remembers the new shapes. A file seen for the first time
  /// or deleted is not a change of shape.
  List<String> changed(Iterable<String> paths) {
    final changed = <String>[];
    for (final path in paths) {
      final source = _read(path);
      if (source == null) {
        _shapes.remove(path);
        continue;
      }
      final shape = shapeOf(source);
      final previous = _shapes[path];
      _shapes[path] = shape;
      if (previous != null && previous != shape) changed.add(path);
    }
    return changed;
  }

  static String? _read(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      // Deleted or unreadable since the event: nothing to compare.
      return null;
    }
  }
}

/// Collects the source of every shape declaration of a unit.
final class _ShapeCollector extends RecursiveAstVisitor<void> {
  final parts = <String>[];

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) =>
      parts.add(node.toSource());

  @override
  void visitFieldDeclaration(FieldDeclaration node) =>
      parts.add(node.toSource());

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) =>
      parts.add(node.toSource());

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) =>
      parts.add(node.toSource());
}
