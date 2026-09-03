import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';

/// On-device storage for the personal profile. Nothing leaves the device
/// except the rendered prompt text sent with each companion turn.
class ProfileStore {
  static const _key = 'user_profile_v1';

  Future<UserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return UserProfile();
    return UserProfile.decode(raw);
  }

  Future<void> save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, profile.encode());
  }
}
