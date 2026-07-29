# Token Cost App - OC Codex — 项目速查

## 仓库结构
- `Package.swift` — SPM 清单，三个 target: `CodexTokenCostCore`, `CodexTokenCostApp`, `CodexTokenCostHelper`
- `Sources/CodexTokenCostCore/` — 核心模块：数据模型、SQLite 客户端、来源发现、设置持久化、分析引擎、余额监控、凭证存储
- `Sources/CodexTokenCostApp/` — 主应用：SwiftUI 视图、Store、App 入口、更新检查
- `Sources/CodexTokenCostHelper/` — 辅助进程：CLI 采集 Codex session JSONL
- `script/build_and_run_codex.sh` — 本地构建/运行/调试/打包脚本
- `docs/` — 架构图和开发手册
- `.github/workflows/` — CI (ci.yml)、自动发布 (release.yml)、CodeQL (codeql.yml)

## 构建命令
```bash
swift build            # Debug 构建
swift build -c release # Release 构建
bash script/build_and_run_codex.sh build  # 仅构建 app
bash script/build_and_run_codex.sh run    # 构建并运行
swift test             # 运行测试
```

## 编码约定
- 所有公开 API 使用 `public` 修饰符，内部实现使用 `private`
- 数据模型遵循 `Codable, Hashable, Identifiable, Sendable`
- UI 组件使用 `TokenCostPalette` 统一主题色，不硬编码颜色
- 文件操作统一经过 `SafeFileStore` 进行沙箱内读写
- 来源扫描通过 `SourceDiscoveryService` 集中管理
- 凭证验证通过 `CredentialCandidateValidating` 协议抽象，测试用 mock 注入
- 浏览器 Cookie 读取使用 `Security.framework` `SecItemCopyMatching`，禁止 fork `/usr/bin/security`
- 更新包自动安装要求 Ed25519 签名 manifest 验证（`UpdateManifest` + `prepareVerifiedUpdate`）

## 关键入口
- App 入口：`Sources/CodexTokenCostApp/App/TokenCostApp.swift` — `@main`
- Helper 入口：`Sources/CodexTokenCostHelper/main.swift`
- 数据模型：`Sources/CodexTokenCostCore/Models.swift`
- 分析引擎：`Sources/CodexTokenCostCore/DashboardAnalytics.swift`
- 余额监控：`Sources/CodexTokenCostCore/Balance/BalanceManager.swift`
- 凭证引导：`Sources/CodexTokenCostCore/Balance/CredentialBootstrapService.swift`
- 凭证验证：`Sources/CodexTokenCostCore/Balance/CredentialCandidateValidator.swift`
- 浏览器 Cookie：`Sources/CodexTokenCostCore/Balance/Providers/BrowserCookieExtractor.swift`
- 加密存储：`Sources/CodexTokenCostCore/Balance/LocalEncryptedCredentialStore.swift`
- 更新检查：`Sources/CodexTokenCostApp/Services/UpdateChecker.swift`
- 开发者模式：`Sources/CodexTokenCostCore/DeveloperMode/DeveloperModePreferences.swift`
