// A library that imports a generated-looking file of a package that does not
// exist.
// ignore_for_file: uri_does_not_exist, unused_import, depend_on_referenced_packages
// The ignore is deliberate: the unresolved import is what the test needs.
import 'package:nope/x.g.dart';
