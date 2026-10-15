// A module written with the explicit API; it imports package:grund
// unhidden, so `Module` here is the core class.
import 'package:grund/grund.dart';

/// A module the generator cannot look into.
Module explicitModule() => Module(id: 'explicit');
