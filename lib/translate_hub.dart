import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class TranslateHub {
  static final TranslateHub shared = TranslateHub._internal();
  TranslateHub._internal();

  static const String _host = "us-central1-translationhub-d60f6.cloudfunctions.net";
  static const String _storageKey = "THub.Translation.Storage";
  static const String _lastSyncKey = "THub.Translation.LastSync";
  
  String _currentLangCode = "en";
  Translation? _translation;
  
  Translation? get translation => _translation;
  
  THLanguageItem? get current {
    return _translation?.languages.where((lang) => lang.code == _currentLangCode).firstOrNull;
  }

  void pickLanguage(String code) {
    _currentLangCode = code;
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

  Future<void> initialize(String apiKey, {Function()? completion}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check cache validity (3 days)
      final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
      const threeDaysInMillis = 3 * 24 * 60 * 60 * 1000;
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      
      if (lastSync > 0 && 
          currentTime - lastSync < threeDaysInMillis &&
          prefs.containsKey(_storageKey)) {
        await _extractTranslation();
        completion?.call();
        return;
      }

      // Fetch from API
      await _fetchFromAPI(apiKey, prefs, completion);
    } catch (e) {
      // On failure, try to use existing cache
      await _extractTranslation();
      completion?.call();
    }
  }

  Future<void> _fetchFromAPI(String apiKey, SharedPreferences prefs, Function()? completion) async {
    try {
      final url = Uri.https(_host, '/getPublicTranslations');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'x-api-key': apiKey,
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
        final decoded = Translation.fromJson(jsonMap);
        _translation = decoded;
        
        // Save to cache
        await prefs.setString(_storageKey, response.body);
        await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      } else {
        // On HTTP error, try to use existing cache
        await _extractTranslation();
      }
    } catch (e) {
      // On failure, try to use existing cache
      await _extractTranslation();
    } finally {
      completion?.call();
    }
  }
}