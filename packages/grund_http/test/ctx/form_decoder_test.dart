import 'package:grund_http/src/ctx/form_decoder.dart';
import 'package:test/test.dart';

void main() {
  test('decodes names and values, + as a space and UTF-8 escapes', () {
    expect(FormDecoder.decode('name=ann+lee&city=K%C3%B6ln'), {
      'name': ['ann lee'],
      'city': ['Köln'],
    });
  });

  test('keeps repeated names in order', () {
    expect(FormDecoder.decode('tag=a&tag=b'), {
      'tag': ['a', 'b'],
    });
  });

  test('a field without = has an empty value; empty fields are skipped', () {
    expect(FormDecoder.decode('flag&&x='), {
      'flag': [''],
      'x': [''],
    });
  });

  test('splits a field at the first =', () {
    expect(FormDecoder.decode('q=a=b'), {
      'q': ['a=b'],
    });
  });

  for (final text in ['a=%zz', 'a=%', 'a=%4', '%C3=x', 'a=%C3']) {
    test('"$text" is a FormatException', () {
      expect(() => FormDecoder.decode(text), throwsFormatException);
    });
  }
}
