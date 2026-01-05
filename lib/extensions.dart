import 'dart:ui';

import 'models.dart';
import 'translate_hub.dart';

extension StringTranslate on String {
  String? get translate {
    final currentCode = TranslateHub.shared.current?.code;
    if (currentCode == null) return null;
    
    return TranslateHub.shared.translation?.translationsByCode[currentCode]?[this];
  }
}

extension THLanguageItemTranslate on THLanguageItem {
  TextDirection get textDirection => direction == 'ltr' ? TextDirection.ltr : TextDirection.rtl;
}