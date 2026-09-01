import 'dart:io';

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

    test('日志自动脱敏 token、密钥和完整设备 ID', () {
      log.record(
        'appToken=secret-value e2eKey=another-secret device=1234567890abcdef',
      );
      final text = log.exportText();
      expect(text, isNot(contains('secret-value')));
      expect(text, isNot(contains('another-secret')));
      expect(text, isNot(contains('1234567890abcdef')));
      expect(text, contains('[REDACTED]'));
      expect(text, contains('12345678…'));
    });

    test('落盘日志可等待写入并可同时清空', () async {
      final directory = await Directory.systemTemp.createTemp('diagnostic-log-');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final persistentLog = DiagnosticLog(directoryOverride: directory);
      await persistentLog.configurePersistence(true);
      persistentLog.record('device=1234567890abcdef appToken=secret');
      await persistentLog.flush();

      final file = File('${directory.path}/diagnostics-v1.log');
      final contents = await file.readAsString();
      expect(contents, contains('12345678…'));
      expect(contents, isNot(contains('secret')));

      persistentLog.clear();
      await persistentLog.flush();
      expect(await file.readAsString(), isEmpty);
    });
  });
}
