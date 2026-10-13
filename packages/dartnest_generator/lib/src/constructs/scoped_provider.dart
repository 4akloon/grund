import '../model/module_model.dart';
import '../model/provider_model.dart';

/// A provider as one module sees it: the provider and the module that
/// declares it.
typedef ScopedProvider = ({ModuleModel owner, ProviderModel provider});
