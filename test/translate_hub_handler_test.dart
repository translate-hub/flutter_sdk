import 'package:flutter_test/flutter_test.dart';

import 'package:translate_hub_handler/translate_hub_handler.dart';

void main() {
  group('Translation.fromJson', () {
    test('parses languages and per-code translation maps', () {
      final translation = Translation.fromJson({
        'languages': [
          {'direction': 'ltr', 'code': 'en', 'name': 'English'},
          {'direction': 'rtl', 'code': 'he', 'name': 'Hebrew'},
        ],
        'en': {'welcome': 'Welcome', 'bye': 'Bye'},
        'he': {'welcome': 'ברוך הבא'},
      });

      expect(translation.languages.map((l) => l.code), ['en', 'he']);
      expect(translation.translationsByCode['en']!['welcome'], 'Welcome');
      expect(translation.translationsByCode['he']!['welcome'], 'ברוך הבא');
    });

    test('ignores non-string values and the languages key', () {
      final translation = Translation.fromJson({
        'languages': [
          {'direction': 'ltr', 'code': 'en', 'name': 'English'},
        ],
        'en': {'ok': 'OK', 'count': 3},
      });

      expect(translation.translationsByCode['en']!['ok'], 'OK');
      // Non-string values are skipped rather than coerced.
      expect(translation.translationsByCode['en']!.containsKey('count'), false);
    });

    test('handles an empty document', () {
      final translation = Translation.fromJson({});
      expect(translation.languages, isEmpty);
      expect(translation.translationsByCode, isEmpty);
    });
  });

  test('THLanguageItem.textDirection maps direction to TextDirection', () {
    const ltr = THLanguageItem(direction: 'ltr', code: 'en', name: 'English');
    const rtl = THLanguageItem(direction: 'rtl', code: 'he', name: 'Hebrew');

    expect(ltr.textDirection.name, 'ltr');
    expect(rtl.textDirection.name, 'rtl');
  });
}