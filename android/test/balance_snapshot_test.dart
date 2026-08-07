import 'package:flutter_test/flutter_test.dart';

import 'package:balance_monitor/models/balance_snapshot.dart';
import 'package:balance_monitor/models/relay_models.dart';

void main() {
  test('解析 opencode_zen snapshot（预估消耗字段）', () {
    final snapshot = BalanceSnapshot.fromJson({
      'provider': 'opencode_zen',
      'fetchedAt': 1700000000,
      'isAvailable': true,
      'totalCostUSD': 12.34,
      'avgCostPerDayUSD': 0.5,
    });
    expect(snapshot.provider, BalanceProvider.opencodeZen);
    expect(snapshot.totalCostUSD, 12.34);
    expect(snapshot.avgCostPerDayUSD, 0.5);
  });

  test('未知 provider 返回 null 而非抛异常', () {
    expect(BalanceProvider.fromRawValue('future_provider'), isNull);
  });

  test('RelayBalanceResponse 跳过解析失败的 snapshot', () {
    final response = RelayBalanceResponse.fromJson({
      'generatedAtMilliseconds': 1700000000,
      'snapshots': [
        {'provider': 'opencode_go', 'fetchedAt': 1700000000, 'isAvailable': true},
        {'provider': 'unknown_provider', 'fetchedAt': 1700000000, 'isAvailable': true},
        {'provider': 'opencode_zen', 'fetchedAt': 1700000000, 'isAvailable': true},
      ],
    });
    expect(response.snapshots.length, 2);
    expect(response.snapshots[0].provider, BalanceProvider.opencodeGo);
    expect(response.snapshots[1].provider, BalanceProvider.opencodeZen);
  });

  test('解析配额窗口消耗速率', () {
    final window = QuotaWindow.fromJson({
      'label': '5小时窗口',
      'usedRatio': 0.3,
      'consumptionRate': {'perHour': 1.5, 'perDay': 36.0, 'confidence': 0.8},
    });
    expect(window.usedRatio, 0.3);
    expect(window.consumptionRate?.perHour, 1.5);
    expect(window.consumptionRate?.perDay, 36.0);
  });

  test('解析货币余额消耗速率', () {
    final entry = BalanceValueEntry.fromJson({
      'label': '余额',
      'currencyCode': 'CNY',
      'amount': 100.0,
      'amountConsumptionRate': {'perHour': 2.0, 'perDay': 48.0, 'confidence': 0.9},
    });
    expect(entry.amount, 100.0);
    expect(entry.amountConsumptionRate?.perDay, 48.0);
  });
}
