import 'package:balance_monitor/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('隐私优先默认值', () async {
    final settings = await AppSettingsStore.load();

    expect(settings.backgroundRefreshEnabled, isFalse);
    expect(settings.realtimeMonitorEnabled, isFalse);
    expect(settings.showSensitiveNotificationContent, isFalse);
    expect(settings.hideSensitiveContentOnLockScreen, isTrue);
    expect(settings.persistDiagnostics, isFalse);
    expect(settings.refreshMinutes, 60);
  });

  test('刷新频率限制为允许值', () async {
    final settings = await AppSettingsStore.load();

    await settings.setRefreshMinutes(30);
    expect(settings.refreshMinutes, 30);
    expect(() => settings.setRefreshMinutes(10), throwsArgumentError);
  });

  test('SharedPreferences 不包含安全凭据字段', () {
    expect(AppSettingsStore.persistedKeys, isNot(contains('appToken')));
    expect(AppSettingsStore.persistedKeys, isNot(contains('e2eKey')));
    expect(AppSettingsStore.persistedKeys, isNot(contains('relayEndpoint')));
  });
}
