import 'package:balance_monitor/models/analytics_sections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const payload = <String, dynamic>{
    'overview': {
      'totalTokens': 1200.0,
      'totalActualTokens': 900.0,
      'totalCostUSD': 3.5,
      'dailyAverageTokens': 300.0,
      'monthlyEstimateTokens': 9000.0,
      'activeDays': 4,
    },
    'cache': {
      'cacheReadTokens': 250.0,
      'cacheWriteTokens': 50.0,
      'hitRate': 0.2,
      'savedCostUSD': 0.4,
      'estimatedCacheReadTokens': 25.0,
      'hasEstimates': true,
    },
    'cost': {
      'providers': [
        {'provider': 'openai', 'tokens': 700.0, 'costUSD': 2.5},
      ],
      'models': [
        {
          'model': 'gpt-5',
          'provider': 'openai',
          'tokens': 700.0,
          'costUSD': 2.5,
        },
      ],
    },
    'usage': {
      'providers': [
        {'provider': 'openai', 'tokens': 700.0},
      ],
      'models': [
        {'model': 'gpt-5', 'provider': 'openai', 'tokens': 700.0},
      ],
    },
    'modelDistribution': {
      'models': [
        {
          'label': 'gpt-5',
          'tokens': 700.0,
          'percentage': 0.7,
          'isOther': false,
        },
      ],
      'providers': [
        {
          'label': 'openai',
          'tokens': 700.0,
          'percentage': 0.7,
          'isOther': false,
        },
      ],
    },
    'trend': {
      'timeZoneIdentifier': 'Asia/Shanghai',
      'days': 30,
      'points': [
        {
          'date': '2026-08-31',
          'actualTokens': 100.0,
          'cacheReadTokens': 20.0,
          'cacheWriteTokens': 5.0,
          'estimatedCacheReadTokens': 2.0,
        },
      ],
    },
    'heatmap': {
      'timeZoneIdentifier': 'Asia/Shanghai',
      'weeks': 52,
      'days': [
        {'date': '2026-08-31', 'tokens': 127.0},
      ],
    },
  };

  test('七类 section 均按 Relay schema 解析', () {
    final result = AnalyticsSections.parse(payload);

    expect(result.errors, isEmpty);
    expect(result.overview?.totalActualTokens, 900);
    expect(result.cache?.hasEstimates, isTrue);
    expect(result.cost?.providers.single.costUSD, 2.5);
    expect(result.usage?.models.single.model, 'gpt-5');
    expect(result.distribution?.models.single.percentage, 0.7);
    expect(result.trend?.points.single.actualTokens, 100);
    expect(result.heatmap?.days.single.tokens, 127);
  });

  test('单个 section 损坏时保留其它 section', () {
    final result = AnalyticsSections.parse({
      ...payload,
      'trend': {'days': -1, 'points': 'invalid'},
    });

    expect(result.overview, isNotNull);
    expect(result.heatmap, isNotNull);
    expect(result.trend, isNull);
    expect(result.errors, contains('trend'));
  });

  test('拒绝负数、NaN 与无限值', () {
    final result = AnalyticsSections.parse({
      'overview': {
        ...payload['overview']! as Map<String, dynamic>,
        'totalTokens': -1,
      },
      'cache': {
        ...payload['cache']! as Map<String, dynamic>,
        'hitRate': double.nan,
      },
    });

    expect(result.overview, isNull);
    expect(result.cache, isNull);
    expect(result.errors, containsAll(['overview', 'cache']));
  });
}
