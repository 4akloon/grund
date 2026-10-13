import 'package:dartnest/dartnest.dart';
import 'package:test/test.dart';

void main() {
  group('Token', () {
    test('equal when name and type match', () {
      expect(
        const Token<String>('db.url'),
        equals(const Token<String>('db.url')),
      );
      expect(Token<String>('db.url'), equals(Token<String>('db.url')));
      expect(
        Token<String>('db.url').hashCode,
        equals(Token<String>('db.url').hashCode),
      );
    });

    test('different name is a different token', () {
      expect(const Token<String>('a'), isNot(equals(const Token<String>('b'))));
    });

    test('different type parameter is a different token', () {
      expect(const Token<String>('a'), isNot(equals(const Token<int>('a'))));
    });

    test('is not equal across a supertype parameter, in both directions', () {
      const narrow = Token<String>('a');
      const wide = Token<Object>('a');
      expect(narrow == wide, isFalse);
      expect(wide == narrow, isFalse);
    });

    test('exposes its type and a readable toString', () {
      const token = Token<int>('port');
      expect(token.type, int);
      expect(token.toString(), 'Token<int>(port)');
    });
  });
}
