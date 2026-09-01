class AnalyticsSections {
  final OverviewSection? overview;
  final CacheSection? cache;
  final MetricsSection? cost;
  final MetricsSection? usage;
  final DistributionSection? distribution;
  final TrendSection? trend;
  final HeatmapSection? heatmap;
  final Set<String> errors;

  const AnalyticsSections({
    this.overview,
    this.cache,
    this.cost,
    this.usage,
    this.distribution,
    this.trend,
    this.heatmap,
    this.errors = const {},
  });

  bool get isEmpty =>
      overview == null &&
      cache == null &&
      cost == null &&
      usage == null &&
      distribution == null &&
      trend == null &&
      heatmap == null;

  factory AnalyticsSections.parse(Map<String, dynamic> json) {
    final errors = <String>{};
    T? parse<T>(String key, T Function(Map<String, dynamic>) decoder) {
      final value = json[key];
      if (value == null) return null;
      try {
        return decoder(_map(value));
      } catch (_) {
        errors.add(key);
        return null;
      }
    }

    return AnalyticsSections(
      overview: parse('overview', OverviewSection.fromJson),
      cache: parse('cache', CacheSection.fromJson),
      cost: parse('cost', MetricsSection.fromJson),
      usage: parse('usage', MetricsSection.fromJson),
      distribution: parse('modelDistribution', DistributionSection.fromJson),
      trend: parse('trend', TrendSection.fromJson),
      heatmap: parse('heatmap', HeatmapSection.fromJson),
      errors: Set.unmodifiable(errors),
    );
  }
}

class OverviewSection {
  final double totalTokens;
  final double totalActualTokens;
  final double totalCostUSD;
  final double dailyAverageTokens;
  final double monthlyEstimateTokens;
  final int activeDays;

  const OverviewSection({
    required this.totalTokens,
    required this.totalActualTokens,
    required this.totalCostUSD,
    required this.dailyAverageTokens,
    required this.monthlyEstimateTokens,
    required this.activeDays,
  });

  factory OverviewSection.fromJson(Map<String, dynamic> json) =>
      OverviewSection(
        totalTokens: _number(json['totalTokens']),
        totalActualTokens: _number(json['totalActualTokens']),
        totalCostUSD: _number(json['totalCostUSD']),
        dailyAverageTokens: _number(json['dailyAverageTokens']),
        monthlyEstimateTokens: _number(json['monthlyEstimateTokens']),
        activeDays: _integer(json['activeDays']),
      );
}

class CacheSection {
  final double cacheReadTokens;
  final double cacheWriteTokens;
  final double hitRate;
  final double savedCostUSD;
  final double estimatedCacheReadTokens;
  final bool hasEstimates;

  const CacheSection({
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.hitRate,
    required this.savedCostUSD,
    required this.estimatedCacheReadTokens,
    required this.hasEstimates,
  });

  factory CacheSection.fromJson(Map<String, dynamic> json) {
    final hitRate = _number(json['hitRate']);
    if (hitRate > 1) throw const FormatException('hitRate exceeds 1');
    return CacheSection(
      cacheReadTokens: _number(json['cacheReadTokens']),
      cacheWriteTokens: _number(json['cacheWriteTokens']),
      hitRate: hitRate,
      savedCostUSD: _number(json['savedCostUSD']),
      estimatedCacheReadTokens: _number(json['estimatedCacheReadTokens']),
      hasEstimates: _boolean(json['hasEstimates']),
    );
  }
}

class ProviderMetric {
  final String provider;
  final double tokens;
  final double? costUSD;

  const ProviderMetric({
    required this.provider,
    required this.tokens,
    this.costUSD,
  });

  factory ProviderMetric.fromJson(Map<String, dynamic> json) => ProviderMetric(
    provider: _string(json['provider']),
    tokens: _number(json['tokens']),
    costUSD: json['costUSD'] == null ? null : _number(json['costUSD']),
  );
}

class ModelMetric {
  final String model;
  final String provider;
  final double tokens;
  final double? costUSD;

  const ModelMetric({
    required this.model,
    required this.provider,
    required this.tokens,
    this.costUSD,
  });

  factory ModelMetric.fromJson(Map<String, dynamic> json) => ModelMetric(
    model: _string(json['model']),
    provider: _string(json['provider']),
    tokens: _number(json['tokens']),
    costUSD: json['costUSD'] == null ? null : _number(json['costUSD']),
  );
}

class MetricsSection {
  final List<ProviderMetric> providers;
  final List<ModelMetric> models;

  const MetricsSection({required this.providers, required this.models});

  factory MetricsSection.fromJson(Map<String, dynamic> json) => MetricsSection(
    providers: _list(json['providers'])
        .map((value) => ProviderMetric.fromJson(_map(value)))
        .toList(growable: false),
    models: _list(
      json['models'],
    ).map((value) => ModelMetric.fromJson(_map(value))).toList(growable: false),
  );
}

class DistributionItem {
  final String label;
  final double tokens;
  final double percentage;
  final bool isOther;

  const DistributionItem({
    required this.label,
    required this.tokens,
    required this.percentage,
    required this.isOther,
  });

  factory DistributionItem.fromJson(Map<String, dynamic> json) {
    final percentage = _number(json['percentage']);
    if (percentage > 1) {
      throw const FormatException('percentage exceeds 1');
    }
    return DistributionItem(
      label: _string(json['label']),
      tokens: _number(json['tokens']),
      percentage: percentage,
      isOther: _boolean(json['isOther']),
    );
  }
}

class DistributionSection {
  final List<DistributionItem> models;
  final List<DistributionItem> providers;

  const DistributionSection({required this.models, required this.providers});

  factory DistributionSection.fromJson(Map<String, dynamic> json) =>
      DistributionSection(
        models: _list(json['models'])
            .map((value) => DistributionItem.fromJson(_map(value)))
            .toList(growable: false),
        providers: _list(json['providers'])
            .map((value) => DistributionItem.fromJson(_map(value)))
            .toList(growable: false),
      );
}

class TrendPoint {
  final String date;
  final double actualTokens;
  final double cacheReadTokens;
  final double cacheWriteTokens;
  final double estimatedCacheReadTokens;

  const TrendPoint({
    required this.date,
    required this.actualTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.estimatedCacheReadTokens,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
    date: _date(json['date']),
    actualTokens: _number(json['actualTokens']),
    cacheReadTokens: _number(json['cacheReadTokens']),
    cacheWriteTokens: _number(json['cacheWriteTokens']),
    estimatedCacheReadTokens: _number(json['estimatedCacheReadTokens']),
  );
}

class TrendSection {
  final String timeZoneIdentifier;
  final int days;
  final List<TrendPoint> points;

  const TrendSection({
    required this.timeZoneIdentifier,
    required this.days,
    required this.points,
  });

  factory TrendSection.fromJson(Map<String, dynamic> json) {
    final days = _integer(json['days']);
    if (days < 1 || days > 366) throw const FormatException('invalid days');
    return TrendSection(
      timeZoneIdentifier: _string(json['timeZoneIdentifier']),
      days: days,
      points: _list(json['points'])
          .map((value) => TrendPoint.fromJson(_map(value)))
          .toList(growable: false),
    );
  }
}

class HeatmapDay {
  final String date;
  final double tokens;

  const HeatmapDay({required this.date, required this.tokens});

  factory HeatmapDay.fromJson(Map<String, dynamic> json) =>
      HeatmapDay(date: _date(json['date']), tokens: _number(json['tokens']));
}

class HeatmapSection {
  final String timeZoneIdentifier;
  final int weeks;
  final List<HeatmapDay> days;

  const HeatmapSection({
    required this.timeZoneIdentifier,
    required this.weeks,
    required this.days,
  });

  factory HeatmapSection.fromJson(Map<String, dynamic> json) {
    final weeks = _integer(json['weeks']);
    if (weeks < 1 || weeks > 53) throw const FormatException('invalid weeks');
    return HeatmapSection(
      timeZoneIdentifier: _string(json['timeZoneIdentifier']),
      weeks: weeks,
      days: _list(json['days'])
          .map((value) => HeatmapDay.fromJson(_map(value)))
          .toList(growable: false),
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('expected object');
}

List<dynamic> _list(Object? value) {
  if (value is List<dynamic>) return value;
  throw const FormatException('expected list');
}

double _number(Object? value) {
  if (value is! num) throw const FormatException('expected number');
  final number = value.toDouble();
  if (!number.isFinite || number < 0) {
    throw const FormatException('invalid number');
  }
  return number;
}

int _integer(Object? value) {
  if (value is! num || value.toInt() != value || value < 0) {
    throw const FormatException('expected non-negative integer');
  }
  return value.toInt();
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('expected non-empty string');
  }
  return value;
}

String _date(Object? value) {
  final text = _string(value);
  if (DateTime.tryParse(text) == null) {
    throw const FormatException('invalid date');
  }
  return text;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('expected bool');
  return value;
}
