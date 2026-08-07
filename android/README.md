# Balance Monitor（安卓端）

Android 手机端余额监控 App，与 macOS 桌面端（Token Cost App）配套，用于随时查看各 AI Provider 的余额与配额。

## 功能

- **扫码配对**：扫描 macOS 桌面端生成的安全配对二维码，建立端到端（E2EE）连接。
- **余额监控**：实时查看 OpenCode Go / Ollama Cloud / Codex / DeepSeek 的余额快照（配额比例、剩余 Credits、货币余额）。
- **端到端加密**：配对信息（App Token + E2EE 密钥）通过 AES-256-GCM 加密，经中继服务器转发，服务器无法解密内容。
- **安全存储**：配对凭证存于 Android Keystore（`flutter_secure_storage`），不落明文到普通存储。
- **忘记设备**：一键撤销服务器上的配对记录并清除本地密钥。

## 架构

采用 **relay（中继）+ 端到端加密** 模式：

```
macOS 桌面端 ──(生成配对二维码)──► Android 手机端
                                     │
                   扫描二维码 → claimPairing(deviceId, pairCode)
                                     │
                    中继服务器（仅转发密文，无法解密）
                                     │
             手机端用 E2EE 密钥加密请求 → 解密响应（余额快照）
```

核心模块：

| 路径 | 说明 |
|------|------|
| `lib/views/dashboard_view.dart` | 主界面：连接状态、余额列表、刷新、忘记设备 |
| `lib/views/pair_scanner_view.dart` | 扫码配对界面（mobile_scanner） |
| `lib/views/balance_card.dart` | 余额卡片（配额/余额/窗口展示） |
| `lib/services/relay_client.dart` | 中继 API 客户端（配对、查询、撤销、删除设备） |
| `lib/services/relay_crypto.dart` | AES-256-GCM 端到端加解密 |
| `lib/services/relay_identity_store.dart` | 配对身份的安全持久化 |
| `lib/models/relay_models.dart` | 配对/信封/查询/响应模型 |
| `lib/models/balance_snapshot.dart` | 余额快照模型 |

安卓端作为中继的 **App 端**：通过 HTTPS 向中继服务发起余额查询请求，中继服务再通过 WebSocket 转发给 macOS 桌面端（PC 端），桌面端返回余额快照后经中继回传。安卓端负责配对交互、余额展示与在线/错误状态恢复。

> **当前状态**：若设备曾被撤销（revoke），需要重新配对后才能继续使用。真实手机端到端（E2E）验证尚未通过，需在设备撤销后重新配对再验证。

## 开发

### 环境要求

- Flutter SDK（stable）+ Dart 3.12+
- JDK 17（Android 构建必需）

### 常用命令

```bash
cd android

flutter pub get          # 安装依赖
flutter analyze          # 静态检查
flutter test             # 单元测试（relay 安全链路）

# Debug 必须显式指定 Development Relay；二维码不携带服务器地址
flutter run --dart-define=RELAY_BASE_URL=http://10.0.2.2:8787
```

Release 只接受构建时注入的 HTTPS Production Endpoint，用户、二维码、SharedPreferences、Intent 或 Deep Link 均不能覆盖。真实 Production URL 不写入 Public Source；正式构建由受保护的 CI Environment 注入。

### 打包发布

推荐使用仓库打包脚本（自动归档到 `android/release/`）：

```bash
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"   # 若系统已安装 JDK 17，脚本会自动回退识别
export RELAY_BASE_URL="${RELAY_BASE_URL:?请先设置受保护的 HTTPS Relay Endpoint}"
bash script/build_android_release.sh          # 构建并归档（版本号读自 pubspec.yaml）
bash script/build_android_release.sh release  # 正式发布（可 RELEASE_VERSION=v1.0.0 覆盖）
bash script/build_android_release.sh help     # 查看用法
```

正式打包还要求 `RELAY_BASE_URL` 和 Release Signing 配置；缺少任一配置会直接失败。构建启用 Flutter obfuscation、R8/resource shrinking，并把 split-debug-info 保留在受忽略的本地目录，不随 APK/AAB 分发。

### release 目录约定

归档目录命名与 macOS 端一致（版本号-时间戳-PID）：

```
android/release/v<版本>-<YYYYMMDD>-<HHMMSS>-<PID>/
├── balance-monitor-<版本>-android-arm64-v8a-release.apk        # 现代设备（主力）
├── balance-monitor-<版本>-android-armeabi-v7a-release.apk      # 旧设备
├── balance-monitor-<版本>-android-x86_64-release.apk           # 模拟器/x86
├── balance-monitor-<版本>-android-universal-release.apk        # 全架构单包
└── balance-monitor-<版本>-android-release.aab                  # Play Store 用
```

> 产物为二进制大文件，`android/release/` 下的 `.apk/.aab/.zip` 已被 `.gitignore` 忽略，经 GitHub Releases 分发。

## 测试

```bash
cd android && flutter test
```

覆盖中继安全链路：二维码拒绝 Endpoint override、固定 Endpoint 校验、E2EE 信封往返与防篡改、配对领取、结构化错误码、requestId 绑定、设备撤销/删除、注册状态检测及 Contract vectors。

> **WebSocket 兼容性经验**：中继服务与 macOS 桌面端之间的 WebSocket 传输必须接受已部署客户端实际使用的帧类型（text frame 与 binary frame 均按 UTF-8 JSON 解析），相关错误需端到端测试验证，不能只依赖单端单元测试。

## 文档

- 与 macOS 端的配对/加密协议见桌面端 `docs/` 相关说明。
- Client-facing Protocol 单独维护在 Public Relay Contract；本仓库使用 `Resources/RelayContract/v1/` 的固定快照运行测试。
- Private Relay 的服务端、Admin、Database 与部署文档不属于 Public App。
