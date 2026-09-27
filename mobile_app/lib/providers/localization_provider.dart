import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_strings.dart';

enum AppLanguage {
  english,
  afaanOromo,
}

class LocalizationProvider with ChangeNotifier {
  AppLanguage _currentLanguage = AppLanguage.english;
  Map<String, String> _strings = AppStrings.english;

  AppLanguage get currentLanguage => _currentLanguage;
  Map<String, String> get strings => _strings;

  String getString(String key) {
    return _strings[key] ?? key;
  }

  String get languageName {
    switch (_currentLanguage) {
      case AppLanguage.english:
        return 'English';
      case AppLanguage.afaanOromo:
        return 'Afaan Oromoo';
    }
  }

  String get languageCode {
    switch (_currentLanguage) {
      case AppLanguage.english:
        return 'en';
      case AppLanguage.afaanOromo:
        return 'om';
    }
  }

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLanguage = prefs.getString('app_language') ?? 'en';
      
      if (savedLanguage == 'om') {
        _currentLanguage = AppLanguage.afaanOromo;
        _strings = AppStrings.afaanOromo;
      } else {
        _currentLanguage = AppLanguage.english;
        _strings = AppStrings.english;
      }
      
      notifyListeners();
      debugPrint('[Localization] Loaded language: $languageName');
    } catch (e) {
      debugPrint('[Localization] Error loading language: $e');
    }
  }

  Future<void> setLanguage(AppLanguage language) async {
    try {
      _currentLanguage = language;
      
      switch (language) {
        case AppLanguage.english:
          _strings = AppStrings.english;
          break;
        case AppLanguage.afaanOromo:
          _strings = AppStrings.afaanOromo;
          break;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language', languageCode);
      
      notifyListeners();
      debugPrint('[Localization] Language changed to: $languageName');
    } catch (e) {
      debugPrint('[Localization] Error setting language: $e');
    }
  }

  void toggleLanguage() {
    if (_currentLanguage == AppLanguage.english) {
      setLanguage(AppLanguage.afaanOromo);
    } else {
      setLanguage(AppLanguage.english);
    }
  }
}
