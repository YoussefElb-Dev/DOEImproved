import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists app preferences: the chosen theme and the profile photo.
class SettingsStore {
  SettingsStore._();

  static const _profileImageKey = 'profile_image_path';
  static const _themeKey = 'app_theme_id';

  // ── theme ───────────────────────────────────────────────────────────

  /// The saved theme's enum name, or null when the student never picked one.
  static Future<String?> themeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey);
  }

  static Future<void> saveThemeId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, id);
  }

  // ── profile photo ───────────────────────────────────────────────────

  static Future<String> profileImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_profileImageKey) ?? '';
  }

  /// Opens the file picker and copies the selected image into app storage.
  /// Returns the persisted path, or null if the user cancelled.
  static Future<String?> pickAndSaveProfileImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return null;

    final src = File(result.files.single.path!);
    final appDir = await getApplicationDocumentsDirectory();
    final ext = result.files.single.extension ?? 'png';
    final dest = File('${appDir.path}/profile_avatar.$ext');
    await src.copy(dest.path);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileImageKey, dest.path);
    return dest.path;
  }

  static Future<void> clearProfileImage() async {
    final path = await profileImagePath();
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileImageKey);
  }
}
