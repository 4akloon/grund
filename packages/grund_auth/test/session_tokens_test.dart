import 'dart:math';

import 'package:grund_auth/src/session/session_tokens.dart';
import 'package:test/test.dart';

void main() {
  test('a token is 43 base64url characters without padding', () {
    final token = SessionTokens().next();

    expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
  });

  test('two tokens differ', () {
    final tokens = SessionTokens();

    expect(tokens.next(), isNot(tokens.next()));
  });

  test('draws from the given random source', () {
    expect(SessionTokens(Random(1)).next(), SessionTokens(Random(1)).next());
  });

  test('isWellFormed accepts a token and refuses other shapes', () {
    final token = SessionTokens().next();

    expect(SessionTokens.isWellFormed(token), isTrue);
    expect(SessionTokens.isWellFormed('$token='), isFalse);
    expect(SessionTokens.isWellFormed(token.substring(1)), isFalse);
    expect(SessionTokens.isWellFormed('${token.substring(1)}+'), isFalse);
  });
}
