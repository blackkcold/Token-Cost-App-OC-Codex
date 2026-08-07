/// 余额快照，供 UI 展示。对应 macOS 端 `BalanceSnapshot` 的核心字段。
enum BalanceProvider {
  opencodeGo('opencode_go', 'OpenCode Go', 0),
  codex('codex', 'Codex', 1),
  opencodeZen('opencode_zen', 'OpenCode Zen', 2),
  deepseek('deepseek', 'DeepSeek', 3),
  ollama('ollama', 'Ollama Cloud', 4);

  final String rawValue;
  final String displayName;
  final int sortOrder;

  const BalanceProvider(this.rawValue, this.displayName, this.sortOrder);

  /// 未知 provider 返回 null，避免 Mac 端新增 provider 导致整个列表解析失败。
  static BalanceProvider? fromRawValue(String value) {
    for (final provider in values) {
      if (provider.rawValue == value) return provider;
    }
    return null;
  }
}

/// 消耗速率（每小时/每天 + 置信度）。
class ConsumptionRate {
  final double perHour;
  final double perDay;
  final double confidence;

  ConsumptionRate({
    this.perHour = 0,
    this.perDay = 0,
    this.confidence = 0,
  });

  factory ConsumptionRate.fromJson(Map<String, dynamic> json) {
    return ConsumptionRate(
      perHour: (json['perHour'] as num?)?.toDouble() ?? 0,
      perDay: (json['perDay'] as num?)?.toDouble() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 配额窗口（时间窗口 + 使用比例 + 消耗速率）。
class QuotaWindow {
  final String label;
  final double? usedRatio;
  final double? remainingRatio;
  final DateTime? resetAt;
  final ConsumptionRate? consumptionRate;

  QuotaWindow({
    required this.label,
    this.usedRatio,
    this.remainingRatio,
    this.resetAt,
    this.consumptionRate,
  });

  factory QuotaWindow.fromJson(Map<String, dynamic> json) {
    final rate = json['consumptionRate'];
    return QuotaWindow(
      label: json['label'] as String? ?? '窗口',
      usedRatio: (json['usedRatio'] as num?)?.toDouble(),
      remainingRatio: (json['remainingRatio'] as num?)?.toDouble(),
      resetAt: _decodeSwiftDate(json['resetAt']),
      consumptionRate: rate is Map<String, dynamic> ? ConsumptionRate.fromJson(rate) : null,
    );
  }
}

/// 单一 Provider 的余额快照。
class BalanceSnapshot {
  final BalanceProvider? provider;
  final DateTime fetchedAt;
  final bool isAvailable;
  final String? errorMessage;
  final double? usagePercent;
  final double? remainingCredits;
  final double? totalCredits;
  final double? usedCredits;
  final String? planType;
  final double? totalCostUSD;
  final double? avgCostPerDayUSD;
  final List<QuotaWindow> quotaWindows;
  final List<BalanceValueEntry> valueEntries;

  BalanceSnapshot({
    required this.provider,
    required this.fetchedAt,
    required this.isAvailable,
    this.errorMessage,
    this.usagePercent,
    this.remainingCredits,
    this.totalCredits,
    this.usedCredits,
    this.planType,
    this.totalCostUSD,
    this.avgCostPerDayUSD,
    this.quotaWindows = const [],
    this.valueEntries = const [],
  });

  factory BalanceSnapshot.fromJson(Map<String, dynamic> json) {
    final quotaWindows = (json['quotaWindows'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(QuotaWindow.fromJson)
            .toList() ??
        const <QuotaWindow>[];
    final valueEntries = (json['valueEntries'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(BalanceValueEntry.fromJson)
            .toList() ??
        const <BalanceValueEntry>[];
    return BalanceSnapshot(
      provider: BalanceProvider.fromRawValue(json['provider'] as String? ?? ''),
      fetchedAt: _decodeSwiftDate(json['fetchedAt']) ?? DateTime.now().toUtc(),
      isAvailable: json['isAvailable'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
      usagePercent: (json['usagePercent'] as num?)?.toDouble(),
      remainingCredits: (json['remainingCredits'] as num?)?.toDouble(),
      totalCredits: (json['totalCredits'] as num?)?.toDouble(),
      usedCredits: (json['usedCredits'] as num?)?.toDouble(),
      planType: json['planType'] as String?,
      totalCostUSD: (json['totalCostUSD'] as num?)?.toDouble(),
      avgCostPerDayUSD: (json['avgCostPerDayUSD'] as num?)?.toDouble(),
      quotaWindows: quotaWindows,
      valueEntries: valueEntries,
    );
  }

  bool get isQuotaType => quotaWindows.isNotEmpty || usagePercent != null;
  bool get isBalanceType => valueEntries.isNotEmpty;

  int get usagePercentInt => usagePercent == null ? 0 : (usagePercent! * 100).round();

  UsageGradient get gradient {
    if (!isAvailable) return UsageGradient.unknown;
    final pct = usagePercent;
    if (pct != null) {
      if (pct <= 0) return UsageGradient.unused;
      if (pct < 0.50) return UsageGradient.low;
      if (pct < 0.80) return UsageGradient.moderate;
      if (pct < 0.95) return UsageGradient.high;
      if (pct < 1.0) return UsageGradient.critical;
      return UsageGradient.exceeded;
    }
    if (valueEntries.isNotEmpty) return UsageGradient.low;
    if (totalCostUSD != null) return UsageGradient.low;
    return UsageGradient.unknown;
  }

  String get shortSummary {
    if (!isAvailable) return '${provider?.displayName ?? '未知'} 不可用';
    final pct = usagePercent;
    if (pct != null) {
      return '${provider?.displayName ?? ''} ${(pct * 100).round()}%';
    }
    if (valueEntries.isNotEmpty) {
      return '${provider?.displayName ?? ''} ${valueEntries.first.amount.toStringAsFixed(2)}';
    }
    return '${provider?.displayName ?? ''} OK';
  }
}

/// 货币余额条目（如 DeepSeek CNY）。
class BalanceValueEntry {
  final String label;
  final String? currencyCode;
  final double amount;
  final double? grantedAmount;
  final double? toppedUpAmount;
  final ConsumptionRate? amountConsumptionRate;

  BalanceValueEntry({
    required this.label,
    this.currencyCode,
    required this.amount,
    this.grantedAmount,
    this.toppedUpAmount,
    this.amountConsumptionRate,
  });

  factory BalanceValueEntry.fromJson(Map<String, dynamic> json) {
    final rate = json['amountConsumptionRate'];
    return BalanceValueEntry(
      label: json['label'] as String? ?? '余额',
      currencyCode: json['currencyCode'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      grantedAmount: (json['grantedAmount'] as num?)?.toDouble(),
      toppedUpAmount: (json['toppedUpAmount'] as num?)?.toDouble(),
      amountConsumptionRate: rate is Map<String, dynamic> ? ConsumptionRate.fromJson(rate) : null,
    );
  }
}

DateTime? _decodeSwiftDate(dynamic value) {
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  if (value is num) {
    const referenceEpochOffsetMilliseconds = 978307200000;
    return DateTime.fromMillisecondsSinceEpoch(
      (value.toDouble() * 1000).round() + referenceEpochOffsetMilliseconds,
      isUtc: true,
    );
  }
  return null;
}

enum UsageGradient {
  unused,
  low,
  moderate,
  high,
  critical,
  exceeded,
  unknown;

  String get label {
    switch (this) {
      case unused: return '未使用';
      case low: return '剩余充足';
      case moderate: return '适中';
      case high: return '接近上限';
      case critical: return '即将用尽';
      case exceeded: return '已超额';
      case unknown: return '未知';
    }
  }
}
