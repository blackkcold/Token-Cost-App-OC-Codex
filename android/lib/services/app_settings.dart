import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsStore extends ChangeNotifier {
  static const _backgroundRefreshKey = 'background_refresh_enabled';
  static const _realtimeMonitorKey = 'realtime_monitor_enabled';
  static const _sensitiveNotificationKey =
      'show_sensitive_notification_content';
  static const _hideOnLockScreenKey = 'hide_sensitive_on_lock_screen';
  static const _developerModeKey = 'developer_mode_enabled';
  static const _persistDiagnosticsKey = 'persist_diagnostics_enabled';
  static const _refreshMinutesKey = 'refresh_minutes';

  static const persistedKeys = <String>{
    _backgroundRefreshKey,
    _realtimeMonitorKey,
    _sensitiveNotificationKey,
    _hideOnLockScreenKey,
    _developerModeKey,
    _persistDiagnosticsKey,
    _refreshMinutesKey,
  };
  static const allowedRefreshMinutes = <int>[15, 30, 60, 120];

  final SharedPreferences _preferences;
  bool backgroundRefreshEnabled;
  bool realtimeMonitorEnabled;
  bool showSensitiveNotificationContent;
  bool hideSensitiveContentOnLockScreen;
  bool developerModeEnabled;
  bool persistDiagnostics;
  int refreshMinutes;

  AppSettingsStore._({
    required this._preferences,
    required this.backgroundRefreshEnabled,
    required this.realtimeMonitorEnabled,
    required this.showSensitiveNotificationContent,
    required this.hideSensitiveContentOnLockScreen,
    required this.developerModeEnabled,
    required this.persistDiagnostics,
    required this.refreshMinutes,
  });

  static Future<AppSettingsStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    final storedMinutes = preferences.getInt(_refreshMinutesKey) ?? 60;
    return AppSettingsStore._(
      preferences: preferences,
      backgroundRefreshEnabled:
          preferences.getBool(_backgroundRefreshKey) ?? false,
      realtimeMonitorEnabled: preferences.getBool(_realtimeMonitorKey) ?? false,
      showSensitiveNotificationContent:
          preferences.getBool(_sensitiveNotificationKey) ?? false,
      hideSensitiveContentOnLockScreen:
          preferences.getBool(_hideOnLockScreenKey) ?? true,
      developerModeEnabled: preferences.getBool(_developerModeKey) ?? false,
      persistDiagnostics: preferences.getBool(_persistDiagnosticsKey) ?? false,
      refreshMinutes: allowedRefreshMinutes.contains(storedMinutes)
          ? storedMinutes
          : 60,
    );
  }

  Future<void> setBackgroundRefreshEnabled(bool value) =>
      _setBool(_backgroundRefreshKey, value, () {
        backgroundRefreshEnabled = value;
      });

  Future<void> setRealtimeMonitorEnabled(bool value) =>
      _setBool(_realtimeMonitorKey, value, () {
        realtimeMonitorEnabled = value;
      });

  Future<void> setShowSensitiveNotificationContent(bool value) =>
      _setBool(_sensitiveNotificationKey, value, () {
        showSensitiveNotificationContent = value;
      });

  Future<void> setHideSensitiveContentOnLockScreen(bool value) =>
      _setBool(_hideOnLockScreenKey, value, () {
        hideSensitiveContentOnLockScreen = value;
      });

  Future<void> setDeveloperModeEnabled(bool value) =>
      _setBool(_developerModeKey, value, () {
        developerModeEnabled = value;
      });

  Future<void> setPersistDiagnostics(bool value) =>
      _setBool(_persistDiagnosticsKey, value, () {
        persistDiagnostics = value;
      });

  Future<void> setRefreshMinutes(int value) {
    if (!allowedRefreshMinutes.contains(value)) {
      throw ArgumentError.value(value, 'value', 'unsupported refresh interval');
    }
    refreshMinutes = value;
    notifyListeners();
    return _preferences.setInt(_refreshMinutesKey, value);
  }

  Future<void> _setBool(String key, bool value, VoidCallback apply) {
    apply();
    notifyListeners();
    return _preferences.setBool(key, value);
  }
}
