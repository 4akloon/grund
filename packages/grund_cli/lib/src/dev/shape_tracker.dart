import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Remembers the shape of Dart files: the declarations a hot reload cannot
/// apply to state that already exists.
///
/// The shape of a file is the source (without comments and formatting) of
/// its top-level variables, fields, constructors and enum values. A
/// changed field or constructor would leave instances created before the
/// reload (the singletons kept by `App.reassemble`) with fields that
/// were never initialized; a changed initializer of a top-level or static
/// variable, or a changed `const`, is not applied by a reload at all. A
/// change of anything else (method bodies, functions, annotations of
/// classes and methods) is reloadable. Every part is prefixed with the
/// name of its enclosing declaration, and each class-like declaration also
/// contributes a header (kind, modifiers, type parameters, `extends`,
/// `with`, `implements`), so moving a field or changing the hierarchy is
/// a change of shape.
///
/// Callers must [remember] every `.dart` file under `lib/` and the entry
/// directory at startup: a file that was never remembered is treated as
/// new. Paths that are not `.dart` files are ignored.
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
    for (final path in paths.where(_isDart)) {
      final source = _read(path);
      if (source != null) _shapes[path] = shapeOf(source);
    }
  }

  /// The [paths] whose shape differs from the one remembered, in the
  /// order given; remembers the new shapes. A file seen for the first time
  /// or deleted is not a change of shape; a deleted file keeps its last
  /// known shape, so a recreated one is compared with it.
  List<String> changed(Iterable<String> paths) {
    final changed = <String>[];
    for (final path in paths.where(_isDart)) {
      final source = _read(path);
      if (source == null) continue;
      final shape = shapeOf(source);
      final previous = _shapes[path];
      _shapes[path] = shape;
      if (previous != null && previous != shape) changed.add(path);
    }
    return changed;
  }

  static bool _isDart(String path) => path.endsWith('.dart');

  static String? _read(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      // Deleted or unreadable since the event: nothing to compare.
      return null;
    }
  }
}

/// Collects the parts of the shape of a unit, each prefixed with the name
/// of its enclosing declaration.
final class _ShapeCollector extends RecursiveAstVisitor<void> {
  final parts = <String>[];
  var _enclosing = '';

  /// Visits the body of [node]; the header (name included) identifies the
  /// declaration, so it is also the prefix of the parts inside.
  void _declaration(Declaration node, void Function() visit) {
    final outer = _enclosing;
    _enclosing = _header(node);
    parts.add('header: $_enclosing');
    visit();
    _enclosing = outer;
  }

  /// The tokens of [node] between its metadata and its body or `;`.
  static String _header(Declaration node) {
    final tokens = <String>[];
    for (
      Token? token = node.firstTokenAfterCommentAndMetadata;
      token != null &&
          !token.isEof &&
          token.lexeme != '{' &&
          token.lexeme != ';';
      token = token.next
    ) {
      tokens.add(token.lexeme);
    }
    return tokens.join(' ');
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) =>
      _declaration(node, () => super.visitClassDeclaration(node));

  @override
  void visitMixinDeclaration(MixinDeclaration node) =>
      _declaration(node, () => super.visitMixinDeclaration(node));

  @override
  void visitEnumDeclaration(EnumDeclaration node) =>
      _declaration(node, () => super.visitEnumDeclaration(node));

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) =>
      _declaration(node, () => super.visitExtensionDeclaration(node));

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) =>
      _declaration(node, () => super.visitExtensionTypeDeclaration(node));

  void _add(AstNode node) => parts.add('$_enclosing: ${node.toSource()}');

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) =>
      _add(node);

  @override
  void visitFieldDeclaration(FieldDeclaration node) => _add(node);

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) => _add(node);

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) => _add(node);
}
