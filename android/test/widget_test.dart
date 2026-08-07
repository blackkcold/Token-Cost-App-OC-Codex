import 'package:flutter_test/flutter_test.dart';
import 'package:balance_monitor/views/dashboard_view.dart';

void main() {
  test('Mac 恢复在线后清除普通离线提示', () {
    expect(
      statusMessageAfterOnlineCheck(
        online: true,
        currentMessage: '已配对，但 Mac 当前离线',
      ),
      isNull,
    );
  });

  test('查询断连后若 Mac 已在线则显示重新刷新提示', () {
    expect(
      statusMessageAfterOnlineCheck(
        online: true,
        currentMessage: '查询失败：Mac 连接已断开，请确认 Mac 端在线',
      ),
      'Mac 已重新连接，请再次刷新余额',
    );
  });

  test('Mac 仍离线时保留查询失败详情', () {
    const message = '查询失败：Mac 连接已断开，请确认 Mac 端在线';
    expect(
      statusMessageAfterOnlineCheck(online: false, currentMessage: message),
      message,
    );
  });
}
