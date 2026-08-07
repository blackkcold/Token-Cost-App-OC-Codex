import 'package:flutter/material.dart';

import '../models/balance_snapshot.dart';

/// 余额卡片，展示单个 Provider 的配额/余额状态。
class BalanceCard extends StatelessWidget {
  final BalanceSnapshot snapshot;

  const BalanceCard({super.key, required this.snapshot});

  Color _gradientColor(UsageGradient g) {
    switch (g) {
      case UsageGradient.unused:
        return Colors.blueGrey;
      case UsageGradient.low:
        return Colors.green;
      case UsageGradient.moderate:
        return Colors.lightGreen;
      case UsageGradient.high:
        return Colors.orange;
      case UsageGradient.critical:
        return Colors.deepOrange;
      case UsageGradient.exceeded:
        return Colors.red;
      case UsageGradient.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _gradientColor(snapshot.gradient);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    snapshot.provider?.displayName ?? '未知 Provider',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusBadge(available: snapshot.isAvailable),
              ],
            ),
            const SizedBox(height: 12),
            if (snapshot.isAvailable) ...[
              if (snapshot.usagePercent != null)
                _QuotaBar(
                  percent: snapshot.usagePercent!,
                  color: color,
                  label: snapshot.gradient.label,
                ),
              if (snapshot.valueEntries.isNotEmpty)
                ...snapshot.valueEntries.map(
                  (e) => _ValueRow(entry: e),
                ),
              if (snapshot.remainingCredits != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '剩余 Credits: ${snapshot.remainingCredits!.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if (snapshot.usedCredits != null && snapshot.totalCredits != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '已用 ${snapshot.usedCredits!.toStringAsFixed(2)} / 共 ${snapshot.totalCredits!.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if (snapshot.totalCostUSD != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '总消耗: \$${snapshot.totalCostUSD!.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if (snapshot.avgCostPerDayUSD != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '日均消耗: \$${snapshot.avgCostPerDayUSD!.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if (snapshot.quotaWindows.isNotEmpty)
                ...snapshot.quotaWindows.map(
                  (w) => _WindowRow(window: w),
                ),
            ] else
              Text(
                snapshot.errorMessage ?? '不可用',
                style: TextStyle(color: Colors.red.shade600),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool available;

  const _StatusBadge({required this.available});

  @override
  Widget build(BuildContext context) {
    final color = available ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        available ? '正常' : '异常',
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}

class _QuotaBar extends StatelessWidget {
  final double percent;
  final Color color;
  final String label;

  const _QuotaBar({
    required this.percent,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('用量 ${(percent * 100).round()}%', style: Theme.of(context).textTheme.bodyMedium),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  final BalanceValueEntry entry;

  const _ValueRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(entry.label),
          Text(
            '${entry.currencyCode ?? ''} ${entry.amount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _WindowRow extends StatelessWidget {
  final QuotaWindow window;

  const _WindowRow({required this.window});

  @override
  Widget build(BuildContext context) {
    final pct = window.usedRatio;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(window.label),
          if (pct != null)
            Text(
              '已用 ${(pct * 100).round()}%',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}
