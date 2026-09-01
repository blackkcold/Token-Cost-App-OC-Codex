import 'package:flutter/material.dart';

import '../models/analytics_sections.dart';
import '../stores/dashboard_store.dart';

class OverviewView extends StatelessWidget {
  final DashboardStore store;

  const OverviewView({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    if (store.loading) return const Center(child: CircularProgressIndicator());
    final overview = store.analytics.overview;
    final cache = store.analytics.cache;
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _StatusBanner(store: store),
          const SizedBox(height: 16),
          if (overview == null)
            const _EmptyCard(
              icon: Icons.monitor_heart_outlined,
              title: '暂无分析数据',
              message: '保持 Mac 在线并下拉刷新；已配对设备会读取最近 5 分钟的加密缓存。',
            )
          else ...[
            Text('使用脉冲', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '来自 Mac 的端到端加密分析快照',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final columns = textScale >= 1.7
                    ? 1
                    : constraints.maxWidth >= 760
                    ? 3
                    : 2;
                final gap = 12.0;
                final cardWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                final cards = [
                  _MetricCard(
                    label: '实际 token',
                    value: formatCompactTokenCount(overview.totalActualTokens),
                    icon: Icons.bolt_outlined,
                  ),
                  _MetricCard(
                    label: '总 token',
                    value: formatCompactTokenCount(overview.totalTokens),
                    icon: Icons.data_usage_outlined,
                  ),
                  _MetricCard(
                    label: '估算成本',
                    value: '\$${overview.totalCostUSD.toStringAsFixed(2)}',
                    icon: Icons.payments_outlined,
                  ),
                  _MetricCard(
                    label: '日均 token',
                    value: formatCompactTokenCount(overview.dailyAverageTokens),
                    icon: Icons.calendar_today_outlined,
                  ),
                  _MetricCard(
                    label: '活跃天数',
                    value: '${overview.activeDays}',
                    icon: Icons.event_available_outlined,
                  ),
                  _MetricCard(
                    label: '缓存命中率',
                    value: cache == null
                        ? '—'
                        : '${(cache.hitRate * 100).toStringAsFixed(1)}%',
                    icon: Icons.cached_outlined,
                  ),
                ];
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final card in cards)
                      SizedBox(width: cardWidth, child: card),
                  ],
                );
              },
            ),
            if (cache != null) ...[
              const SizedBox(height: 20),
              _CacheCard(cache: cache),
            ],
          ],
          if (store.analytics.errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '部分分析模块无法解析：${store.analytics.errors.join('、')}。其它数据仍可使用。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  static String _compact(double value) => formatCompactTokenCount(value);
}

String formatCompactTokenCount(double value) {
  if (value >= 100000000) return _trimCompactDecimal(value / 100000000, '亿');
  if (value >= 10000) return _trimCompactDecimal(value / 10000, '万');
  return value.toStringAsFixed(0);
}

String _trimCompactDecimal(double value, String suffix) =>
    '${value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}$suffix';

class _StatusBanner extends StatelessWidget {
  final DashboardStore store;

  const _StatusBanner({required this.store});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final online = store.pcOnline;
    final message =
        store.statusMessage ?? (online ? 'Mac 在线，数据链路正常' : '等待连接状态');
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: online
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(online ? Icons.shield : Icons.shield_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            if (store.lastUpdatedAt != null)
              Text(
                '${store.lastUpdatedAt!.hour.toString().padLeft(2, '0')}:${store.lastUpdatedAt!.minute.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _CacheCard extends StatelessWidget {
  final CacheSection cache;

  const _CacheCard({required this.cache});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('缓存效率', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: cache.hitRate.clamp(0, 1)),
            const SizedBox(height: 12),
            Text(
              '读取 ${OverviewView._compact(cache.cacheReadTokens)} · 写入 ${OverviewView._compact(cache.cacheWriteTokens)} · 节省 \$${cache.savedCostUSD.toStringAsFixed(2)}',
            ),
            if (cache.hasEstimates)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('包含展示口径估算值，不影响计费。'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
