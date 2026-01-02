class THLanguageItem {
  final String direction;
  final String code;
  final String name;

  const THLanguageItem({
    required this.direction,
    required this.code,
    required this.name,
  });

  factory THLanguageItem.fromJson(Map<String, dynamic> json) {
    return THLanguageItem(
      direction: json['direction'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'direction': direction,
      'code': code,
      'name': name,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is THLanguageItem &&
        other.direction == direction &&
        other.code == code &&
        other.name == name;
  }

  @override
  int get hashCode => direction.hashCode ^ code.hashCode ^ name.hashCode;
}

class Translation {
  final List<THLanguageItem> languages;
  final Map<String, Map<String, String>> translationsByCode;

  const Translation({
    required this.languages,
    required this.translationsByCode,
  });

  factory Translation.fromJson(Map<String, dynamic> json) {
    final List<THLanguageItem> languages = [];
    final Map<String, Map<String, String>> translationsDict = {};

    // Extract languages
    if (json.containsKey('languages')) {
      final languagesJson = json['languages'] as List<dynamic>;
      for (final languageJson in languagesJson) {
        final languageItem = THLanguageItem.fromJson(languageJson as Map<String, dynamic>);
        languages.add(languageItem);
      }
    }

    // Extract language code dictionaries
    json.forEach((key, value) {
      if (key != 'languages' && value is Map<String, dynamic>) {
        try {
          final translationMap = <String, String>{};
          value.forEach((translationKey, translationValue) {
            if (translationValue is String) {
              translationMap[translationKey] = translationValue;
            }
          });
          translationsDict[key] = translationMap;
        } catch (e) {
          // Skip invalid entries
        }
      }
    });

    return Translation(
      languages: languages,
      translationsByCode: translationsDict,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'languages': languages.map((lang) => lang.toJson()).toList(),
    };
    
    translationsByCode.forEach((key, value) {
      json[key] = value;
    });
    
    return json;
  }
}