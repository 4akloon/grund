import 'package:grund_annotations/grund_annotations.dart';

import '../config/config_module.dart';
import 'role.dart';

/// Looks up the role an API key grants.
@Injectable()
final class ApiKeys {
  /// Reads the keys from the [apiKeys] configuration value.
  ApiKeys(@Inject(apiKeys) this._roles);

  final Map<String, Role> _roles;

  /// The role [key] grants, or `null` for an unknown key.
  Role? roleOf(String key) => _roles[key];
}
