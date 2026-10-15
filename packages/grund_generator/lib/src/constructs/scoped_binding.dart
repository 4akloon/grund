import '../model/binding_model.dart';
import '../model/module_model.dart';

/// A binding together with the module that declares it.
typedef ScopedBinding = ({ModuleModel owner, BindingModel binding});
