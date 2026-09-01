import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analytics_sections.dart';
import '../stores/dashboard_store.dart';
import 'overview_view.dart' show formatCompactTokenCount;

class ChartsView extends StatefulWidget {
  final DashboardStore store;

  const ChartsView({super.key, required this.store});

  @override
  State<ChartsView> createState() => _ChartsViewState();
}

class _ChartsViewState extends State<ChartsView> {
  int _trendDays = 7;

  @override
  Widget build(BuildContext context) {
    final analytics = widget.store.analytics;
    if (analytics.trend == null &&
        analytics.heatmap == null &&
        analytics.distribution == null &&
        analytics.usage == null) {
      return RefreshIndicator(
        onRefresh: widget.store.refresh,
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: const [
            SizedBox(height: 80),
            Icon(Icons.query_stats_outlined, size: 56),
            SizedBox(height: 16),
            Text('暂无图表数据', textAlign: TextAlign.center),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: widget.store.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (analytics.trend != null)
            _ChartCard(
              title: '每日趋势',
              trailing: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 天')),
                  ButtonSegment(value: 30, label: Text('30 天')),
                ],
                selected: {_trendDays},
                onSelectionChanged: (value) {
                  setState(() => _trendDays = value.single);
                },
              ),
              child: _TrendChart(
                trend: analytics.trend!,
                visibleDays: _trendDays,
              ),
            ),
          if (analytics.heatmap != null) ...[
            const SizedBox(height: 16),
            _ChartCard(
              title: '52 周活跃热力图',
              child: _HeatmapChart(section: analytics.heatmap!),
            ),
          ],
          if (analytics.distribution != null) ...[
            const SizedBox(height: 16),
            _ChartCard(
              title: '模型分布',
              child: _DistributionChart(items: analytics.distribution!.models),
            ),
          ],
          if (analytics.usage != null) ...[
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Provider 用量排行',
              child: _RankingChart(items: analytics.usage!.providers),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _ChartCard({required this.title, required this.child, this.trailing});

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
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final TrendSection trend;
  final int visibleDays;

  const _TrendChart({required this.trend, required this.visibleDays});

  @override
  Widget build(BuildContext context) {
    final points = trend.points.length <= visibleDays
        ? trend.points
        : trend.points.sublist(trend.points.length - visibleDays);
    if (points.isEmpty) return const Text('所选范围没有数据');
    final actual = <FlSpot>[];
    final cache = <FlSpot>[];
    for (var index = 0; index < points.length; index++) {
      actual.add(FlSpot(index.toDouble(), points[index].actualTokens));
      cache.add(
        FlSpot(
          index.toDouble(),
          points[index].cacheReadTokens +
              points[index].estimatedCacheReadTokens,
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    final summary =
        '最近 $visibleDays 天，实际 token ${points.fold<double>(0, (sum, item) => sum + item.actualTokens).toStringAsFixed(0)}，缓存读取 ${points.fold<double>(0, (sum, item) => sum + item.cacheReadTokens + item.estimatedCacheReadTokens).toStringAsFixed(0)}';
    return Semantics(
      label: summary,
      child: Column(
        children: [
          SizedBox(
            height: 240,
            child: LineChart(
              LineChartData(
                minY: 0,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.outlineVariant.withValues(alpha: 0.45),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: const FlTitlesData(
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      maxIncluded: false,
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: actual,
                    color: colors.primary,
                    barWidth: 3,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: cache,
                    color: colors.tertiary,
                    barWidth: 2,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            children: [
              _Legend(color: colors.primary, label: '实际 token'),
              _Legend(color: colors.tertiary, label: '缓存读取'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatmapChart extends StatelessWidget {
  final HeatmapSection section;

  const _HeatmapChart({required this.section});

  @override
  Widget build(BuildContext context) {
    final maxTokens = section.days.fold<double>(
      0,
      (maximum, day) => math.max(maximum, day.tokens),
    );
    final activeDays = section.days.where((day) => day.tokens > 0).length;
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label:
          '过去 ${section.weeks} 周共 $activeDays 个活跃日，最高单日 ${maxTokens.toStringAsFixed(0)} token',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 132,
            width: double.infinity,
            child: CustomPaint(
              painter: _HeatmapPainter(
                days: section.days,
                weeks: section.weeks,
                baseColor: color,
                emptyColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                maxTokens: maxTokens,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('少'),
              const SizedBox(width: 8),
              for (final opacity in const [0.12, 0.28, 0.48, 0.72, 1.0])
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: opacity),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              const SizedBox(width: 4),
              const Text('多'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<HeatmapDay> days;
  final int weeks;
  final Color baseColor;
  final Color emptyColor;
  final double maxTokens;

  const _HeatmapPainter({
    required this.days,
    required this.weeks,
    required this.baseColor,
    required this.emptyColor,
    required this.maxTokens,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    var bestColumns = 1;
    var bestCell = 0.0;
    for (
      var candidateColumns = 1;
      candidateColumns <= weeks;
      candidateColumns++
    ) {
      final weekRows = (weeks + candidateColumns - 1) ~/ candidateColumns;
      final candidateCell = math.min(
        (size.width - gap * (candidateColumns - 1)) / candidateColumns,
        (size.height - gap * (weekRows * 7 - 1)) / (weekRows * 7),
      );
      if (candidateCell > bestCell) {
        bestCell = candidateCell;
        bestColumns = candidateColumns;
      }
    }
    final columns = bestColumns;
    final weekRows = (weeks + columns - 1) ~/ columns;
    final cell = bestCell;
    final gridWidth = cell * columns + gap * (columns - 1);
    final gridHeight = cell * weekRows * 7 + gap * (weekRows * 7 - 1);
    final startX = math.max(0, (size.width - gridWidth) / 2);
    final startY = math.max(0, (size.height - gridHeight) / 2);
    final paint = Paint();
    for (var index = 0; index < days.length && index < weeks * 7; index++) {
      final week = index ~/ 7;
      final weekday = index % 7;
      final column = week % columns;
      final row = week ~/ columns;
      final tokens = days[index].tokens;
      final intensity = maxTokens <= 0
          ? 0.0
          : math.sqrt(tokens / maxTokens).clamp(0.0, 1.0);
      paint.color = tokens <= 0
          ? emptyColor
          : baseColor.withValues(alpha: 0.12 + intensity * 0.88);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          startX + column * (cell + gap),
          startY + (row * 7 + weekday) * (cell + gap),
          cell,
          cell,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.maxTokens != maxTokens;
}

class _DistributionChart extends StatelessWidget {
  final List<DistributionItem> items;

  const _DistributionChart({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('没有分布数据');
    final scheme = Theme.of(context).colorScheme;
    final palette = [
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
      scheme.outline,
    ];
    final summary = items
        .map(
          (item) =>
              '${item.label} ${(item.percentage * 100).toStringAsFixed(1)}%',
        )
        .join('，');
    return Semantics(
      label: '模型分布：$summary',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final chart = SizedBox.square(
            dimension: compact ? 210 : 240,
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 54,
                sectionsSpace: 3,
                sections: [
                  for (var index = 0; index < items.length; index++)
                    PieChartSectionData(
                      value: items[index].tokens,
                      color: palette[index % palette.length],
                      radius: 42,
                      title:
                          '${(items[index].percentage * 100).toStringAsFixed(0)}%',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
            ),
          );
          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < items.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _Legend(
                    color: palette[index % palette.length],
                    label:
                        '${items[index].label} · ${(items[index].percentage * 100).toStringAsFixed(1)}%',
                  ),
                ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: chart),
              legend,
            ],
          );
        },
      ),
    );
  }
}

class _RankingChart extends StatelessWidget {
  final List<ProviderMetric> items;

  const _RankingChart({required this.items});

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]..sort((a, b) => b.tokens.compareTo(a.tokens));
    if (sorted.isEmpty) return const Text('没有排行数据');
    final maxTokens = sorted.first.tokens;
    return Column(
      children: [
        for (final item in sorted.take(8))
          Semantics(
            label: '${item.provider}，${item.tokens.toStringAsFixed(0)} token',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(item.provider, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: maxTokens <= 0 ? 0 : item.tokens / maxTokens,
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 72,
                    child: Text(
                      formatCompactTokenCount(item.tokens),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(label)),
      ],
    );
  }
}
