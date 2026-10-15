import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';

/// How the builder recognises the files the generator wrote: a name the
/// generator uses, and its header.
abstract final class GeneratedOutputs {
  /// The file name ending of generated files, `X.g.dart` for `x.dart`.
  static const suffix = '.g.dart';

  /// Whether [path] is named like a generated file; a file of that name
  /// may still be hand-written, [hasHeader] decides.
  static bool hasGeneratedName(String path) => path.endsWith(suffix);

  /// Whether [content] starts with the header of the generator.
  static bool hasHeader(String content) =>
      content.startsWith(LibraryWriter.header);

  /// Whether [library] is a file the generator wrote.
  static bool isOutput(LibraryElement library) =>
      hasGeneratedName('${library.uri}') &&
      hasHeader(library.firstFragment.source.contents.data);
}
