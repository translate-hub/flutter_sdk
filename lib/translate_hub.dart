import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class TranslateHubConfig {
  final String apiKey;
  final String? fallbackFile;
  final bool offline;

  const TranslateHubConfig({
    required this.apiKey,
    this.fallbackFile,
    this.offline = false,
  });
}

class TranslateHub {
  static final TranslateHub shared = TranslateHub._internal();
  TranslateHub._internal();

  static const String _checkInUrl =
      'https://us-central1-translationhub-d60f6.cloudfunctions.net/syncTranslationsSDK';

  static const String _storageKey   = 'THub.Translation.Storage';
  static const String _lastSyncKey  = 'THub.Translation.LastSync';
  static const String _languageKey  = 'THub.Translation.Language';
  static const String _mauUserIdKey = 'THub.MAU.UserId';
  static const String _defaultFallbackFileName = 'translations';

  static const int _cacheLifetimeMillis = 3 * 24 * 60 * 60 * 1000;

  String _currentLangCode = 'en';
  String? _fallbackFileName;
  Translation? _translation;

  Translation? get translation => _translation;

  THLanguageItem? get current {
    return _translation?.languages
        .where((lang) => lang.code == _currentLangCode)
        .firstOrNull;
  }

  void pickLanguage(String code) {
    _currentLangCode = code;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_languageKey, code);
    });
  }

  String _generateUuid() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<String> _getDeviceId(SharedPreferences prefs) async {
    final existing = prefs.getString(_mauUserIdKey);
    if (existing != null) return existing;
    final id = _generateUuid();
    await prefs.setString(_mauUserIdKey, id);
    return id;
  }

  Future<void> initialize(TranslateHubConfig config) async {
    if (config.fallbackFile != null) {
      _fallbackFileName = config.fallbackFile;
    }

    if (config.offline) {
      _translation = await _loadFallbackTranslation();
      await _resolveLanguage();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final isCacheFresh = lastSync > 0 &&
        now - lastSync < _cacheLifetimeMillis &&
        prefs.containsKey(_storageKey);

    if (isCacheFresh) {
      await _extractTranslation();
      await _resolveLanguage();
      return;
    }

    await _checkIn(config, prefs);
    await _resolveLanguage();
  }

  Future<void> _checkIn(TranslateHubConfig config, SharedPreferences prefs) async {
    try {
      final deviceId = await _getDeviceId(prefs);
      final response = await http.get(
        Uri.parse(_checkInUrl),
        headers: {
          'X-API-Key': config.apiKey,
          'X-Device-ID': deviceId,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
        final decoded = Translation.tryFromJson(jsonMap);
        if (decoded != null) {
          _translation = decoded;
          await prefs.setString(_storageKey, response.body);
          await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
          return;
        }
      }
    } catch (ex) {
      print(ex.toString());
    }

    await _extractTranslation();
    _translation ??= await _loadFallbackTranslation();
  }

  Future<void> _extractTranslation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
        _translation = Translation.tryFromJson(jsonMap);
        if (_translation == null) {
          await prefs.remove(_storageKey);
        }
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    }
  }

  Future<Translation?> _loadFallbackTranslation() async {
    final fileName = _fallbackFileName ?? _defaultFallbackFileName;
    final name = fileName.replaceAll('.json', '');
    try {
      final jsonString = await rootBundle.loadString('assets/$name.json');
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return Translation.tryFromJson(jsonMap);
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveLanguage() async {
    final codes = _translation?.languages.map((l) => l.code).toSet() ?? {};
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString(_languageKey);
    if (savedLang != null && codes.contains(savedLang)) {
      _currentLangCode = savedLang;
    } else {
      final deviceLang = PlatformDispatcher.instance.locale.languageCode;
      _currentLangCode = codes.contains(deviceLang) ? deviceLang : 'en';
    }
  }
}
