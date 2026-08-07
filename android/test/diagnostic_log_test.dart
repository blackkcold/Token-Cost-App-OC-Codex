import 'package:balance_monitor/services/diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticLog', () {
    late DiagnosticLog log;

    setUp(() {
      log = DiagnosticLog();
    });

    test('record 与 all 按最新在前返回', () {
      log.record('first');
      log.record('second');
      final all = log.all();
      expect(all.length, 2);
      expect(all.first.message, 'second');
      expect(all.last.message, 'first');
    });

    test('环形容量限制到 200 条', () {
      for (var i = 0; i < 250; i++) {
        log.record('msg-$i');
      }
      expect(log.length, 200);
      final all = log.all();
      // 最新在前，因此第一条是 msg-249
      expect(all.first.message, 'msg-249');
      // 最旧的 msg-0..49 被淘汰，msg-50 成为最旧
      expect(all.last.message, 'msg-50');
    });

    test('clear 清空全部', () {
      log.record('a');
      log.record('b');
      log.clear();
      expect(log.length, 0);
      expect(log.all(), isEmpty);
    });

    test('listen 回调触发', () {
      final seen = <String>[];
      log.listen((entry) => seen.add(entry.message));
      log.record('hello');
      expect(seen, ['hello']);
    });

    test('exportText 按行输出含时间戳', () {
      log.record('x');
      final text = log.exportText();
      expect(text, contains('x'));
      expect(text.split('\n').length, greaterThanOrEqualTo(2));
    });
  });
}
