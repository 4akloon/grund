import 'package:grund/testing.dart';
import 'package:grund_auth/grund_auth.dart';
import 'package:test/test.dart';

Matcher _refused(String part) => throwsA(
  isA<SessionConfigError>().having((e) => e.message, 'message', contains(part)),
);

void main() {
  test('the defaults are valid', () {
    expect(const SessionConfig().validate, returnsNormally);
  });

  test('a cookie name that is not a token is refused', () {
    expect(
      const SessionConfig(cookieName: 'my sid').validate,
      _refused('cookieName'),
    );
    expect(
      const SessionConfig(cookieName: '').validate,
      _refused('cookieName'),
    );
  });

  test('a maxAge under one second is refused', () {
    const config = SessionConfig(maxAge: Duration(milliseconds: 999));

    expect(config.validate, _refused('maxAge'));
  });

  test('SameSite=None without secure is refused', () {
    const config = SessionConfig(secure: false, sameSite: SameSitePolicy.none);

    expect(config.validate, _refused('SameSite=None'));
  });

  test('a __Host- or __Secure- name without secure is refused', () {
    for (final name in ['__Host-sid', '__secure-sid']) {
      final config = SessionConfig(cookieName: name, secure: false);

      expect(config.validate, _refused('prefix'));
    }
  });

  test('the cookie attributes carry secure and sameSite', () {
    const config = SessionConfig(
      secure: false,
      sameSite: SameSitePolicy.strict,
    );

    final attributes = config.attributes(maxAge: const Duration(hours: 1));

    expect(attributes.secure, isFalse);
    expect(attributes.sameSite, SameSitePolicy.strict);
    expect(attributes.httpOnly, isTrue);
    expect(attributes.path, '/');
    expect(attributes.maxAge, const Duration(hours: 1));
  });

  test('SessionModule refuses an invalid config when the app starts', () {
    expect(
      TestApp.start(
        root: const SessionModule(config: SessionConfig(cookieName: 'a b')),
      ),
      throwsA(isA<SessionConfigError>()),
    );
  });
}
