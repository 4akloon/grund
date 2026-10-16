import 'dart:convert';

import 'package:grund_auth/grund_auth.dart';
import 'package:test/test.dart';

void main() {
  test('writes the attributes in a fixed order', () {
    final cookie = SetCookie(
      'sid',
      'abc',
      attributes: const CookieAttributes(maxAge: Duration(days: 7)),
    );

    expect(
      cookie.toHeader(),
      'sid=abc; Max-Age=604800; Path=/; Secure; HttpOnly; SameSite=Lax',
    );
  });

  test('leaves out Max-Age, Secure and HttpOnly when they are off', () {
    final cookie = SetCookie(
      'theme',
      'dark',
      attributes: const CookieAttributes(
        path: '/app',
        secure: false,
        httpOnly: false,
        sameSite: SameSitePolicy.strict,
      ),
    );

    expect(cookie.toHeader(), 'theme=dark; Path=/app; SameSite=Strict');
  });

  test('an empty value with Max-Age=0 deletes a cookie', () {
    final cookie = SetCookie(
      'sid',
      '',
      attributes: const CookieAttributes(maxAge: Duration.zero),
    );

    expect(cookie.toHeader(), startsWith('sid=; Max-Age=0; '));
  });

  for (final name in ['', 'a b', 'a;b', 'a=b', 'a,b', 'a\r\nb', 'ä', '"a"']) {
    test('the name ${Uri.encodeFull(name)} is refused', () {
      expect(() => SetCookie(name, 'v'), throwsA(isA<CookieFormatError>()));
    });
  }

  for (final value in [
    ' ',
    '"',
    ',',
    ';',
    r'\',
    '\t',
    '\x7f',
    'ä',
    '\r',
    '\n',
    '\x00',
  ]) {
    test('the value ${jsonEncode(value)} is refused', () {
      expect(() => SetCookie('n', value), throwsA(isA<CookieFormatError>()));
    });
  }

  test('a value cannot add a header or a cookie (RF2)', () {
    expect(
      () => SetCookie('sid', 'x\r\nSet-Cookie: admin=1'),
      throwsA(isA<CookieFormatError>()),
    );
  });

  test('a path with ; or a line break is refused (RF2)', () {
    for (final path in [
      '/; Domain=evil.test',
      '/\r\nx: y',
      '/\x00',
      '/\x7f',
      '/ä',
    ]) {
      expect(
        () => SetCookie('n', 'v', attributes: CookieAttributes(path: path)),
        throwsA(isA<CookieFormatError>()),
      );
    }
  });

  test('a negative maxAge is refused', () {
    expect(
      () => SetCookie(
        'n',
        'v',
        attributes: const CookieAttributes(maxAge: Duration(seconds: -1)),
      ),
      throwsA(isA<CookieFormatError>()),
    );
  });

  for (final path in ['', 'app', '.']) {
    test('the path ${jsonEncode(path)} is refused', () {
      expect(
        () => SetCookie('n', 'v', attributes: CookieAttributes(path: path)),
        throwsA(isA<CookieFormatError>()),
      );
    });
  }

  test('a positive maxAge under one second is refused', () {
    expect(
      () => SetCookie(
        'n',
        'v',
        attributes: const CookieAttributes(maxAge: Duration(milliseconds: 999)),
      ),
      throwsA(isA<CookieFormatError>()),
    );
  });

  test('a maxAge of exactly one second is written as Max-Age=1', () {
    final cookie = SetCookie(
      'n',
      'v',
      attributes: const CookieAttributes(maxAge: Duration(seconds: 1)),
    );

    expect(cookie.toHeader(), contains('Max-Age=1;'));
  });

  test('SameSite=None without Secure is refused', () {
    expect(
      () => SetCookie(
        'n',
        'v',
        attributes: const CookieAttributes(
          secure: false,
          sameSite: SameSitePolicy.none,
        ),
      ),
      throwsA(isA<CookieFormatError>()),
    );
  });
}
