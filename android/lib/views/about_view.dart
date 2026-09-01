import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutView extends StatefulWidget {
  const AboutView({super.key});

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  String _version = '读取中…';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version}+${info.buildNumber}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(
            Icons.shield_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Balance Monitor',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text('版本 $_version', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          const _InfoCard(
            title: '数据路径',
            body:
                'Mac 聚合本地 OpenCode / Codex 数据，经 Private Relay 转发端到端加密信封；Relay 无法读取余额或分析内容。',
          ),
          const _InfoCard(
            title: '安全边界',
            body:
                'App Token 与 E2EE 密钥只保存在 Android Keystore。Production Relay 地址仅由 release 构建注入，二维码、设置和外部 Intent 均不能覆盖。',
          ),
          const _InfoCard(
            title: '协议与许可',
            body: 'Relay Contract 1.2 · MIT License',
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body),
          ],
        ),
      ),
    );
  }
}
