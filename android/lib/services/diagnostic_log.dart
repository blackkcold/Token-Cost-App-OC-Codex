import 'package:flutter/foundation.dart';

/// 诊断日志分类，用于按阶段分组定位中继/查询/配对问题。
enum DiagnosticCategory {
  connection,
  query,
  pairing,
  registration,
  device;

  String get label => switch (this) {
        connection => '连接',
        query => '查询',
        pairing => '配对',
        registration => '注册',
        device => '设备',
      };
}

/// 单条诊断日志。
class DiagnosticEntry {
  final DateTime timestamp;
  final String message;
  final DiagnosticCategory category;

  const DiagnosticEntry({
    required this.timestamp,
    required this.message,
    this.category = DiagnosticCategory.connection,
  });
}

/// 内存环形诊断日志：保留最近 [maxEntries] 条，供开发者面板排查连接/查询问题。
/// 仅存于内存，不落盘、不包含明文凭据（appToken / e2eKey / pairCode）。
///
/// 线程安全说明：Flutter 为单线程模型，所有 HTTP 回调与 UI 操作都在主 isolate，
/// 因此 [record] 等操作不会跨线程并发访问 [_entries]，无需加锁。
class DiagnosticLog {
  static const int _maxEntries = 200;

  final List<DiagnosticEntry> _entries = [];
  final List<ValueChanged<DiagnosticEntry>> _listeners = [];

  static final DiagnosticLog instance = DiagnosticLog();

  void record(String message, {DiagnosticCategory category = DiagnosticCategory.connection}) {
    final entry = DiagnosticEntry(timestamp: DateTime.now(), message: message, category: category);
    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
    for (final listener in List.of(_listeners)) {
      listener(entry);
    }
  }

  /// 最新在前。
  List<DiagnosticEntry> all() => List.unmodifiable(_entries.reversed);

  /// 按分类过滤，最新在前。
  List<DiagnosticEntry> byCategory(DiagnosticCategory category) =>
      List.unmodifiable(_entries.where((e) => e.category == category).toList().reversed);

  int get length => _entries.length;

  void clear() {
    _entries.clear();
  }

  /// 订阅新增日志（用于实时刷新诊断面板）。返回取消函数。
  VoidCallback listen(ValueChanged<DiagnosticEntry> listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// 导出为可复制的文本（最新在前，含时间戳）。
  String exportText() {
    final buffer = StringBuffer();
    for (final entry in all()) {
      final time = entry.timestamp.toLocal().toString();
      buffer.writeln('[$time][${entry.category.label}] ${entry.message}');
    }
    return buffer.toString();
  }
}
