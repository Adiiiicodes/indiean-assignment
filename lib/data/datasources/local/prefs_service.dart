import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  PrefsService(SharedPreferences preferences) : _preferences = preferences;

  final SharedPreferences _preferences;

  String? getString(String key) => _read(() => _preferences.getString(key));

  bool? getBool(String key) => _read(() => _preferences.getBool(key));

  Future<void> setString(String key, String value) =>
      _mutate(() => _preferences.setString(key, value));

  Future<void> setBool(String key, bool value) =>
      _mutate(() => _preferences.setBool(key, value));

  Future<void> remove(String key) => _mutate(() => _preferences.remove(key));

  Future<void> clear() => _mutate(_preferences.clear);

  Future<void> reload() async {
    try {
      await _preferences.reload();
    } catch (_) {
      throw const StorageException();
    }
  }

  T? _read<T>(T? Function() operation) {
    try {
      return operation();
    } catch (_) {
      throw const StorageException();
    }
  }

  Future<void> _mutate(Future<bool> Function() operation) async {
    try {
      if (await operation()) {
        return;
      }
    } catch (_) {
      throw const StorageException();
    }
    throw const StorageException();
  }
}
