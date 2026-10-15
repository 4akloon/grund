import 'package:analyzer/dart/element/element.dart';
import 'package:grund_generator/grund_generator.dart';

/// How the builder recognises the files the generator wrote: a name the
/// generator uses, and its header.
abstract final class GeneratedOutputs {
  /// The file name endings of generated files: a module library and the
  /// part of an `@Api` library.
  static const suffixes = ['_module.g.dart', '_api.g.dart'];

  /// Whether [path] is named like a generated file; a file of that name
  /// may still be hand-written, [hasHeader] decides.
  static bool hasGeneratedName(String path) => suffixes.any(path.endsWith);

  /// Whether [content] starts with the header of the generator.
  static bool hasHeader(String content) =>
      content.startsWith(LibraryWriter.header);

  /// Whether [library] is a file the generator wrote.
  static bool isOutput(LibraryElement library) =>
      hasGeneratedName('${library.uri}') &&
      hasHeader(library.firstFragment.source.contents.data);
}
