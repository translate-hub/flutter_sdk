import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Fetches the translations file published for your project.
///
/// The file is served straight from Firebase Storage, so there is no backend in
/// the request path: [initialize] performs a single HTTP GET on the SDK URL
/// issued in the TranslateHub dashboard. That URL embeds a download token which
/// is the only credential guarding the file — treat it like an API key and keep
/// it out of public repositories. Revoking a customer drops their token, after
/// which the URL answers 403 and the SDK falls back to its cache or bundled asset.
class TranslateHub {
  static final TranslateHub shared = TranslateHub._internal();
  TranslateHub._internal();

  static const String _storageKey = "THub.Translation.Storage";
  static const String _lastSyncKey = "THub.Translation.LastSync";
  static const String _etagKey = "THub.Translation.ETag";
  static const String _languageKey = "THub.Translation.Language";
  static const String _defaultFallbackFileName = "translations";

  /// How long a cached copy is used before revalidating with the server.
  static const int _cacheLifetimeMillis = 3 * 24 * 60 * 60 * 1000;

  String _currentLangCode = "en";
  String? _fallbackFileName = 'translations';
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
      await prefs.remove(_etagKey);
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

  /// Load the translations, from cache when it is still fresh and from the
  /// network otherwise.
  ///
  /// [translationsUrl] is the SDK URL copied from the TranslateHub dashboard.
  /// Pass [offline] to skip the network entirely and use the bundled asset, and
  /// [fallbackFile] to name that asset (defaults to `assets/translations.json`).
  Future<void> initialize(
    String translationsUrl, {
    String? fallbackFile,
    bool offline = false,
  }) async {
    // Store fallback configuration
    if (fallbackFile != null) {
      _fallbackFileName = fallbackFile;
    }

    // If offline mode, only use the bundled JSON file
    if (offline) {
      _translation = await _loadFallbackTranslation();
      await _resolveLanguage();
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // Check cache validity
      final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      if (lastSync > 0 &&
          currentTime - lastSync < _cacheLifetimeMillis &&
          prefs.containsKey(_storageKey)) {
        await _extractTranslation();
        await _resolveLanguage();
        return;
      }

      // Fetch from Storage with enhanced fallback
      await _fetchFromUrl(translationsUrl);
    } catch (e) {
      // On failure, try cache first, then fallback
      await _extractTranslation();
      _translation ??= await _loadFallbackTranslation();
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

  Future<void> _fetchFromUrl(String translationsUrl) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final headers = <String, String>{'Accept': 'application/json'};

      // Revalidate instead of re-downloading when nothing changed:
      // an unchanged file answers 304 with no body.
      final cachedETag = prefs.getString(_etagKey);
      if (cachedETag != null && prefs.containsKey(_storageKey)) {
        headers['If-None-Match'] = cachedETag;
      }

      final response = await http
          .get(Uri.parse(translationsUrl), headers: headers)
          .timeout(const Duration(seconds: 30));

      switch (response.statusCode) {
        case 200:
          try {
            final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
            _translation = Translation.fromJson(jsonMap);

            // Save to cache
            await prefs.setString(_storageKey, response.body);
            await prefs.setInt(
                _lastSyncKey, DateTime.now().millisecondsSinceEpoch);
            final etag = response.headers['etag'];
            if (etag != null) {
              await prefs.setString(_etagKey, etag);
            }
          } catch (e) {
            // If decoding fails, keep whatever is cached (don't use fallback).
            await _extractTranslation();
          }
          break;

        case 304:
          // Cached copy is still current; just restart the cache window.
          await _extractTranslation();
          await prefs.setInt(
              _lastSyncKey, DateTime.now().millisecondsSinceEpoch);
          break;

        default:
          // On HTTP error (403 means the token was revoked or the URL is
          // stale), try cache first, then the bundled fallback.
          await _extractTranslation();
          _translation ??= await _loadFallbackTranslation();
      }
    } catch (e) {
      // Network error occurred - try cache first, then fallback
      await _extractTranslation();
      _translation ??= await _loadFallbackTranslation();
    }
  }
}