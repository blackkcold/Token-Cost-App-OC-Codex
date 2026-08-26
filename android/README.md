# Balance Monitor（安卓端）

Android 手机端余额监控 App，与 macOS 桌面端（Token Cost App）配套，用于随时查看各 AI Provider 的余额与配额。

## 功能

- **扫码配对**：扫描 macOS 桌面端生成的安全配对二维码，建立端到端（E2EE）连接。
- **余额监控**：实时查看 OpenCode Go / Ollama Cloud / Codex / DeepSeek 的余额快照（配额比例、剩余 Credits、货币余额）。
- **端到端加密**：配对信息（App Token + E2EE 密钥）通过 AES-256-GCM 加密，经中继服务器转发，服务器无法解密内容。
- **安全存储**：配对凭证存于 Android Keystore（`flutter_secure_storage`），不落明文到普通存储。
- **全量分析**：按需获取 overview / cache / cost / usage / modelDistribution / trend / heatmap 七类分析 section。
- **有界缓存**：section 使用 RFC 1950 zlib 解压（单项 128 KiB、总计 512 KiB）并写入设备隔离的 AES-GCM 缓存，5 分钟后失效。
- **终端生命周期**：Contract 1.2 使用 `PENDING → ACTIVE` 两阶段激活；仅 `ACTIVE` 终端可查询，七天无已接受的用户查询后过期。
- **撤销当前手机**：只撤销当前 `keyVersion` 对应的手机终端并清除本地密钥，保留 Mac 注册；网络撤销失败时保留凭据以便重试。

## 架构

采用 **relay（中继）+ 端到端加密** 模式：

```
macOS 桌面端 ──(生成配对二维码)──► Android 手机端
                                     │
                   扫描二维码 → claimPairing(deviceId, pairCode)
                                     │
                    中继服务器（仅转发密文，无法解密）
                                     │
             Mac 激活 PENDING 终端 → 手机用版本绑定的 E2EE 密钥查询
                                     → 解密响应（余额快照）
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

> **兼容边界**：Contract 1.2 客户端拒绝缺少 `keyVersion` 或结构化终端状态的旧 Relay 响应，不静默降级。终端被撤销、替换或过期后需要重新扫码配对。

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

Release 只接受构建时注入的 HTTPS Production Endpoint，用户、二维码、SharedPreferences、Intent 或 Deep Link 均不能覆盖。真实 Production URL 不写入 Public Source；正式构建在本地手动执行，签名使用本地 `key.properties` 与被 `.gitignore` 忽略的 `.jks`，不依赖 CI 注入签名。

### 打包发布

推荐使用仓库打包脚本（自动归档到工作区 `App-Builds/vA.BCD.E-YYYYMMDD-HHMM/android/`）：

```bash
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"   # 若系统已安装 JDK 17，脚本会自动回退识别
export RELAY_BASE_URL="${RELAY_BASE_URL:?请先设置受保护的 HTTPS Relay Endpoint}"
bash script/build_android_release.sh          # 构建并归档（版本号读自 pubspec.yaml）
bash script/build_android_release.sh release  # 正式发布（可 ANDROID_VERSION=1.001.0+1001000 覆盖）
bash script/build_android_release.sh help     # 查看用法
```

正式打包还要求 `RELAY_BASE_URL` 和本地 Release Signing 配置；缺少任一配置会直接失败。签名使用本地 `android/key.properties`（storeFile 指向被 `.gitignore` 忽略的 `android/app/keystore/*.jks`），不写入仓库、不依赖 CI 注入。构建启用 Flutter obfuscation、R8/resource shrinking，并把 split-debug-info 保留在受忽略的本地目录，不随 APK/AAB 分发。

Android 版本独立于 macOS git tag，格式固定为 `A.BCD.E+code`：`A≥1`、`BCD=001–999`、`E=0–9`，且 `code = A×1,000,000 + BCD×1,000 + E`、上限为 `2,100,000,000`。同一个 `A.BCD.E` 只发布一次；需要重发时先递增 `E`。`ANDROID_VERSION` 与 `pubspec.yaml` 读取值在 build/release 两种模式下都会执行相同强校验。

> **打包策略**：不打包 QA 或 Debug 版。归档到 `App-Builds/` 的产物均为带签名正式版（`release` 模式），供正式环境手动测试。

### App-Builds 目录约定

发布二进制归档到工作区级 `App-Builds/` 目录（精确大小写 `App-Builds`），布局与 macOS 端一致：

```
App-Builds/vA.BCD.E-YYYYMMDD-HHMM/android/
├── balance-monitor-vA.BCD.E-YYYYMMDD-HHMM-android-arm64-v8a-release.apk
├── balance-monitor-vA.BCD.E-YYYYMMDD-HHMM-android-armeabi-v7a-release.apk
├── balance-monitor-vA.BCD.E-YYYYMMDD-HHMM-android-x86_64-release.apk
├── balance-monitor-vA.BCD.E-YYYYMMDD-HHMM-android-universal-release.apk
└── balance-monitor-vA.BCD.E-YYYYMMDD-HHMM-android-release.aab
```

> 本地默认在工作区根目录的 `App-Builds/`（各仓库的 sibling，不在仓库内）。Android 产物为二进制大文件，经 GitHub Releases 分发，不提交到仓库。Android 版本独立于 macOS git tag，产物手动上传到 macOS 的 tag Release：先本地执行 `bash script/build_android_release.sh release`，再用 `gh release upload <macOS-tag> App-Builds/vA.BCD.E-YYYYMMDD-HHMM/android/*` 上传到对应 tag 的 Release。

## 测试

```bash
cd android && flutter test
```

覆盖中继安全链路：二维码拒绝 Endpoint override、固定 Endpoint 校验、E2EE 信封往返与防篡改、`keyVersion` 绑定、PENDING 查询拒绝、结构化错误码、requestId/requestNonce 双重绑定、query single-flight、65 KiB 流式上限、RFC 1950 压缩炸弹拒绝、加密 section 缓存、终端撤销、注册状态检测及 Contract vectors。

> **WebSocket 兼容性经验**：中继服务与 macOS 桌面端之间的 WebSocket 传输必须接受已部署客户端实际使用的帧类型（text frame 与 binary frame 均按 UTF-8 JSON 解析），相关错误需端到端测试验证，不能只依赖单端单元测试。

## 文档

- 与 macOS 端的配对/加密协议见桌面端 `docs/` 相关说明。
- Client-facing Protocol 单独维护在 Public Relay Contract；本仓库使用 `Resources/RelayContract/v1/` 的固定快照运行测试。
- Private Relay 的服务端、Admin、Database 与部署文档不属于 Public App。
