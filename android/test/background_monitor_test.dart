import 'package:balance_monitor/models/balance_snapshot.dart';
import 'package:balance_monitor/services/background_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('默认通知不暴露余额或 Provider 明细', () {
    final text = NotificationContentPolicy.text(
      showSensitiveContent: false,
      snapshots: [
        BalanceSnapshot.fromJson({
          'provider': 'opencode_go',
          'fetchedAt': 1700000000,
          'isAvailable': true,
          'remainingCredits': 1234.0,
        }),
      ],
    );

    expect(text, '余额监控已启用，数据已安全刷新');
    expect(text, isNot(contains('1234')));
    expect(text, isNot(contains('OpenCode')));
  });

  test('用户显式允许后才展示脱敏摘要', () {
    final text = NotificationContentPolicy.text(
      showSensitiveContent: true,
      snapshots: [
        BalanceSnapshot.fromJson({
          'provider': 'opencode_go',
          'fetchedAt': 1700000000,
          'isAvailable': true,
          'remainingCredits': 1234.0,
        }),
      ],
    );

    expect(text, contains('OpenCode Go'));
    expect(text, contains('1234'));
  });
}
