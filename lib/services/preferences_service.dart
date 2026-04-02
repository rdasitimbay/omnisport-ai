import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Onboarding ---
  bool get hasSeenOnboarding => _prefs?.getBool('has_seen_onboarding') ?? false;
  Future<void> setHasSeenOnboarding(bool value) async {
    await _prefs?.setBool('has_seen_onboarding', value);
  }

  // --- Language ---
  // Return null if not set yet, so we know to show the Language Picker
  String? get preferredLanguage => _prefs?.getString('preferred_language');
  Future<void> setPreferredLanguage(String langCode) async {
    await _prefs?.setString('preferred_language', langCode);
  }
}
