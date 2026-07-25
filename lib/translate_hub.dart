import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// The two values a customer app is given in the TranslateHub dashboard, plus
/// optional offline behaviour.
///
/// [ownerId] and [token] identify one customer's published translations; the
/// Storage bucket is a fixed property of the TranslateHub deployment and is not
/// passed here.
class TranslateHubConfig {
  /// The TranslateHub account (owner) the translations belong to.
  final String ownerId;

  /// This app's download token — the credential guarding the file. Treat it
  /// like an API key and keep it out of public repositories.
  final String token;

  /// Optional bundled asset (`assets/<fallbackFile>.json`) used in offline mode
  /// or when the network and cache are both unavailable.
  final String? fallbackFile;

  /// Skip the network entirely and load only the bundled asset.
  final bool offline;

  const TranslateHubConfig({
    required this.ownerId,
    required this.token,
    this.fallbackFile,
    this.offline = false,
  });
}

/// Fetches the translations file published for your project.
///
/// The file is served straight from Firebase Storage, so there is no backend in
/// the request path: [initialize] builds the file's URL from the [ownerId] and
/// [token] in [TranslateHubConfig] and performs a single HTTP GET. The token is
/// the only credential guarding the file; revoking a customer drops it, after
/// which the URL answers 403 and the SDK falls back to its cache or bundled asset.
class TranslateHub {
  static final TranslateHub shared = TranslateHub._internal();
  TranslateHub._internal();

  /// Firebase Storage bucket for the TranslateHub deployment. Fixed for every
  /// customer, so it lives here rather than in the config. If the backend
  /// project ever moves, update this constant and release a new SDK version.
  static const String _bucket = "translationhub-d60f6.firebasestorage.app";

  static const String _storageKey    = 'THub.Translation.Storage';
  static const String _lastSyncKey   = 'THub.Translation.LastSync';
  static const String _etagKey       = 'THub.Translation.ETag';
  static const String _languageKey   = 'THub.Translation.Language';
  static const String _mauUserIdKey  = 'THub.MAU.UserId';
  static const String _mauCheckinKey = 'THub.MAU.Checkin'; // stored as "YYYY-MM"
  static const String _defaultFallbackFileName = 'translations';

  static const String _trackUrl =
      'https://us-central1-translationhub-d60f6.cloudfunctions.net/trackActiveUser';

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

  // ---------------------------------------------------------------------------
  // MAU check-in
  // ---------------------------------------------------------------------------

  String _currentMonth() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  String _generateUuid() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<String> _getMauUserId(SharedPreferences prefs) async {
    final existing = prefs.getString(_mauUserIdKey);
    if (existing != null) return existing;
    final id = _generateUuid();
    await prefs.setString(_mauUserIdKey, id);
    return id;
  }

  /// Fire-and-forget: POST to [_trackUrl] at most once per calendar month per
  /// device. Only commits the stored month on HTTP 200 so a network failure
  /// retries on the next app launch within the same month.
  void _checkIn(String token) {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final month = _currentMonth();
        if (prefs.getString(_mauCheckinKey) == month) return;

        final userId = await _getMauUserId(prefs);
        final response = await http
            .post(
              Uri.parse(_trackUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'token': token, 'userId': userId}),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          await prefs.setString(_mauCheckinKey, month);
        }
      } catch (_) {
        // Silently ignore — retries on the next app launch this month.
      }
    }());
  }

  // ---------------------------------------------------------------------------

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

  /// Build the published file's URL the same way `getDownloadURL` would, from
  /// the constant [_bucket] and the customer's owner id and token.
  String _buildUrl(TranslateHubConfig config) {
    final objectPath =
        Uri.encodeComponent('public_translations/${config.ownerId}/translations.json');
    return 'https://firebasestorage.googleapis.com/v0/b/$_bucket/o/'
        '$objectPath?alt=media&token=${config.token}';
  }

  /// Load the translations, from cache when it is still fresh and from the
  /// network otherwise.
  ///
  /// [config] carries the `ownerId` and `token` from the TranslateHub dashboard.
  /// Set `config.offline` to skip the network and use the bundled asset, and
  /// `config.fallbackFile` to name that asset (defaults to `assets/translations.json`).
  Future<void> initialize(TranslateHubConfig config) async {
    // Store fallback configuration
    if (config.fallbackFile != null) {
      _fallbackFileName = config.fallbackFile;
    }

    // If offline mode, only use the bundled JSON file
    if (config.offline) {
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
        _checkIn(config.token);
        return;
      }

      // Fetch from Storage with enhanced fallback
      await _fetchFromUrl(_buildUrl(config), config.token);
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

  Future<void> _fetchFromUrl(String translationsUrl, String token) async {
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
            _checkIn(token);
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
          _checkIn(token);
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