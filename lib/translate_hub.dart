import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class TranslateHub {
  static final TranslateHub shared = TranslateHub._internal();
  TranslateHub._internal();

  static String _host = "us-central1-translationhub-d60f6.cloudfunctions.net";
  static set host(String value) => _host = value;
  static const String _storageKey = "THub.Translation.Storage";
  static const String _lastSyncKey = "THub.Translation.LastSync";
  static const String _defaultFallbackFileName = "translations";
  static const String _languageKey = "THub.Translation.Language";

  String _currentLangCode = "en";
  String? _fallbackFileName = 'translations';
  Translation? _translation;
  
  Translation? get translation => _translation;
  
  THLanguageItem? get current {
    return _translation?.languages.where((lang) => lang.code == _currentLangCode).firstOrNull;
  }

  void pickLanguage(String code) {
    _currentLangCode = code;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_languageKey, code);
    });
  }

  Future<void> _extractTranslation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
        _translation = Translation.fromJson(jsonMap);
      }
    } catch (e) {
      // If decoding fails, clear corrupt cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    }
  }

  Future<Translation?> _loadFallbackTranslation() async {
    final fileName = _fallbackFileName ?? _defaultFallbackFileName;
    
    // Remove .json extension if provided
    final fileNameWithoutExtension = fileName.replaceAll('.json', '');
    final assetPath = 'assets/$fileNameWithoutExtension.json';
    
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      _translation = Translation.fromJson(jsonMap);
      return _translation;
    } catch (e) {
      // Silently fail if fallback JSON is invalid or not found
      return null;
    }
  }

  Future<void> initialize(String apiKey, {String? fallbackFile, bool offline = false}) async {
    // Store fallback configuration
    if (fallbackFile != null) {
      _fallbackFileName = fallbackFile;
    }

    // If offline mode, only use JSON file
    if (offline) {
      _translation = await _loadFallbackTranslation();
      await _resolveLanguage();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check cache validity (3 days)
      final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
      const threeDaysInMillis = 5 * 1000;
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      
      if (lastSync > 0 &&
          currentTime - lastSync < threeDaysInMillis &&
          prefs.containsKey(_storageKey)) {
        await _extractTranslation();
        await _resolveLanguage();
        return;
      }

      // Fetch from API with enhanced fallback
      await _fetchFromAPI(apiKey);
    } catch (e) {
      // On failure, try cache first, then fallback
      await _extractTranslation();
      if (_translation == null) {
        _translation = await _loadFallbackTranslation();
      }
    }

    await _resolveLanguage();
  }

  Future<void> _resolveLanguage() async {
    final codes = _translation?.languages.map((l) => l.code).toSet() ?? {};

    // 1. Saved language from SharedPreferences
    // 2. Device language
    // 3. English fallback
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString(_languageKey);
    if (savedLang != null && codes.contains(savedLang)) {
      _currentLangCode = savedLang;
    } else {
      final deviceLang = PlatformDispatcher.instance.locale.languageCode;
      _currentLangCode = codes.contains(deviceLang) ? deviceLang : 'en';
    }
  }

  Future<void> _fetchFromAPI(String apiKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = Uri.https(_host, '/getPublicTranslations');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'x-api-key': apiKey,
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        try {
          final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
          final decoded = Translation.fromJson(jsonMap);
          _translation = decoded;
          
          // Save to cache
          await prefs.setString(_storageKey, response.body);
          await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
        } catch (e) {
          // If decoding fails from API, try to use existing cache (don't use fallback)
          await _extractTranslation();
        }
      } else {
        // On HTTP error, try cache first, then fallback
        await _extractTranslation();
        if (_translation == null) {
          _translation = await _loadFallbackTranslation();
        }
      }
    } catch (e) {
      // Network error occurred - try cache first, then fallback
      await _extractTranslation();
      if (_translation == null) {
        _translation = await _loadFallbackTranslation();
      }
    }
  }
}