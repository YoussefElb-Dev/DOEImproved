import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled settings for NVIDIA NIM transcript extraction.
///
/// The API key is deliberately kept out of SharedPreferences and transcript
/// JSON. On iOS, flutter_secure_storage writes it to the Keychain.
class NimPreferences {
  const NimPreferences({
    this.enabled = false,
    this.hasApiKey = false,
    this.gradeLevel,
  });

  final bool enabled;
  final bool hasApiKey;

  /// The student's current grade, used as app context. A transcript's printed
  /// historical grade remains part of the official record and is not changed.
  final String? gradeLevel;

  NimPreferences copyWith({
    bool? enabled,
    bool? hasApiKey,
    String? gradeLevel,
    bool clearGradeLevel = false,
  }) {
    return NimPreferences(
      enabled: enabled ?? this.enabled,
      hasApiKey: hasApiKey ?? this.hasApiKey,
      gradeLevel: clearGradeLevel ? null : gradeLevel ?? this.gradeLevel,
    );
  }
}

class NimSettingsStore {
  NimSettingsStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _apiKeyKey = 'nvidia_nim_api_key';
  static const _enabledKey = 'nvidia_nim_transcript_enabled';
  static const _gradeLevelKey = 'student_grade_level_override';

  final FlutterSecureStorage _secureStorage;

  Future<NimPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _secureStorage.read(key: _apiKeyKey);
    return NimPreferences(
      enabled: prefs.getBool(_enabledKey) ?? false,
      hasApiKey: key != null && key.trim().isNotEmpty,
      gradeLevel: _clean(prefs.getString(_gradeLevelKey)),
    );
  }

  Future<String?> readApiKey() async {
    return _clean(await _secureStorage.read(key: _apiKeyKey));
  }

  Future<void> saveApiKey(String value) async {
    final key = value.trim();
    if (!key.startsWith('nvapi-') || key.length < 20) {
      throw const FormatException('Enter a valid NVIDIA API key.');
    }
    await _secureStorage.write(key: _apiKeyKey, value: key);
  }

  Future<void> clearApiKey() => _secureStorage.delete(key: _apiKeyKey);

  Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  Future<void> saveGradeLevel(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final grade = _clean(value);
    if (grade == null) {
      await prefs.remove(_gradeLevelKey);
    } else {
      await prefs.setString(_gradeLevelKey, grade);
    }
  }

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
