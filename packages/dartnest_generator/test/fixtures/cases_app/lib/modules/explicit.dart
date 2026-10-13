// A module written with the explicit API; it imports package:dartnest
// unhidden, so `Module` here is the core class.
import 'package:dartnest/dartnest.dart';

/// A module the generator cannot look into.
Module explicitModule() => Module(id: 'explicit');
