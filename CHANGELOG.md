# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- _No new features in this release._

## [v1.0.3] - 2026-07-29

> 相对 `v1.0.2` 的累计变更。**维护版本**：凭证引导重构为「本地加密缓存优先 → 浏览器/Profile 验证链」模型，新增 Ed25519 签名 update manifest 流式下载校验，修复 BalanceManager timeout sentinel 竞态。

### Added

- **Ed25519 签名 update manifest**：`UpdateChecker` 新增 `prepareVerifiedUpdate(from:)` 流程，从 GitHub Release 提取 `.update-manifest.json`（含 version/bundleIdentifier/architecture/assetName/assetSize/sha256/signature），先验证版本、Bundle ID、架构、文件名、长度和 SHA-256，再以流式方式下载到权限受限 staging 目录，最大 512MB，任何失败清理临时产物。构建脚本新增 `write_update_manifest()` 生成签名 manifest，CI workflow 注入 `UPDATE_MANIFEST_PRIVATE_KEY_PEM` / `UPDATE_MANIFEST_PUBLIC_KEY_B64` secrets 并将 manifest 作为 Release asset 上传（`UpdateChecker.swift`、`UpdateCheckerModel.swift`、`script/build_and_run_codex.sh`、`.github/workflows/release.yml`）。
- **新增长本地化 key**：新增 32 个 trend/skills/settings/pricing 相关中英双语本地化键（趋势标题与副标题、热力图、余额折叠、Skills 清除搜索/返回总览、Ollama 实验性功能说明、计费参考头部说明、MiMo Credits 消耗规则、总成本口径）（`Localizable.strings` 中英双语）。
- **新增测试**：`UpdateManifestTests`（Ed25519 签名 manifest 验证、canonical data 构造、公钥缺失/签名错误/元数据不匹配等边界）、`PathUtilitiesSecurityTests`（路径穿越安全）、`CredentialBootstrapServiceTests` 扩展覆盖按浏览器/Profile 验证链路（`Tests/`）。

### Changed

- **凭证引导重构为按浏览器/Profile 验证链**：`CredentialBootstrapService.bootstrapFromBrowser` 从「3 次批量解密浏览器 Cookie」改为「先验证本地加密缓存 → 失败后按浏览器/Profile 逐个验证候选 Cookie → 认证失败才继续下一项」。引入 `CredentialCandidateValidator` 协议（`LiveCredentialCandidateValidator` 通过实际 Provider API 验证），网络不可用时保留本地缓存。新增 `CredentialCandidateValidator.swift`（`CredentialBootstrapService.swift`、`BrowserCookieExtractor.swift`、`CredentialCandidateValidator.swift`）。
- **`BrowserCookieExtractor` 候选列表化**：新增 `credentialCandidates()` / `ollamaCookieCandidates()` 返回带 `source` 的候选列表（去重），原 `extractCredentials()` / `extractOllamaCookie()` 改为返回首个候选。`fetchEncryptionKey` 从 fork `/usr/bin/security` 进程改为 `Security.framework` `SecItemCopyMatching` + `kSecUseAuthenticationUI = kSecUseAuthenticationUISkip`，无法静默读取时直接跳过，不触发系统授权弹窗（`BrowserCookieExtractor.swift`）。
- **AppPreferences 备份逻辑抽取**：`save()` 中的备份轮转逻辑抽取为 `SettingsBackupRotation.backupIfPresent`，消除 `timestamp()` / `rotateBackups()` / `backupExistingPreferencesIfNeeded()` 重复代码（`AppPreferences.swift`、`SettingsStore.swift`）。
- **CodexHelperRunner / PathUtilities 改进**：Helper runner 错误处理增强，PathUtilities 路径穿越加固补充测试覆盖（`CodexHelperRunner.swift`、`PathUtilities.swift`）。
- **CodexAnalytics 调整**：analytics 计算路径微调（`CodexAnalytics.swift`）。
- **SECURITY.md / README.md 文案更新**：反映凭证引导新流程（本地加密缓存优先 → 浏览器验证兜底）和签名 manifest 更新校验（`SECURITY.md`、`README.md`）。

### Fixed

- **BalanceManager timeout sentinel 竞态**：取消时哨兵的 `CancellationError` 被捕获后生成虚假 `.unavailable` 快照，通过 `upsertSnapshot()` 覆盖真实的 `.opencodeGo` 结果。改为区分 cancelled sentinel 与真实 provider 完成，sentinel 不再生成虚假快照，`upsertSnapshot` 不再被取消哨兵污染（`BalanceManager.swift`、`BalanceRefreshScheduler.swift`）。
- **SleepingMockChecker `try?` bug**：`try?` 吞掉了真实的断言错误，导致超时测试假绿。改为显式捕获并传播错误（`SleepingMockChecker`）。

### Security

- **签名 manifest 更新校验**：自动安装要求 Release 同时提供 Ed25519 签名 manifest；客户端先验证版本、Bundle ID、架构、文件名、长度和 SHA-256，再以流式方式下载到权限受限 staging 目录，限制最大体积 512MB，任何失败都会清理临时产物。缺少 manifest 的历史 Release 不进入自动安装流程（`UpdateChecker.swift`、`SECURITY.md`）。
- **凭证引导安全边界**：余额监控启用后先验证 App 的本地加密缓存；缓存有效时不读取浏览器。缓存无效或缺失时，按浏览器/Profile 顺序逐个验证候选 Cookie，认证失败才继续下一项；网络不可用时保留本地缓存。成功候选写入内存与本地加密缓存；全部耗尽时 UI 显示未找到 Cookie，OSLog 只记录来源与失败类别，不记录 Cookie、密钥或完整路径（`CredentialBootstrapService.swift`、`SECURITY.md`）。
- **浏览器 Keychain 静默读取**：`fetchEncryptionKey` 改用 `Security.framework` `SecItemCopyMatching` + `kSecUseAuthenticationUI = kSecUseAuthenticationUISkip`，已有「Always Allow」授权静默返回，无授权不弹窗；无法静默读取时直接跳过该浏览器（`BrowserCookieExtractor.swift`、`SECURITY.md`）。

## [v1.0.2] - 2026-07-29

### Added

- **LiquidGlassButtonStyle**：新增 SwiftUI `ButtonStyle` 子类，仅通过 `scaleEffect(0.96)` + `opacity(0.7)` 提供非彩色按压反馈，并显式遵循 Reduce Motion；不进入系统 tint 管线。用于悬浮面板 widget 操作按钮（`LiquidGlassButtonStyle.swift`、`BalanceFloatingPanelView.swift`）。
- **订阅周期设置（开发者模式）**：计费方案 tab 每个 Provider 卡片新增可折叠的「订阅周期设置」区域（需开启开发者模式）。支持按日/按月粒度切换、快捷预设（按月/按季度/按年自动填充起止日期）、自定义起止日期选择。新增 `periodTotalCost(for:)` 方法按订阅周期折算总成本（按月粒度用 Calendar 月+天/该月天数，按日粒度用 monthlyUSD/30.4375×天数），总览页和菜单栏在开发者模式开启时展示「订阅期总成本」。DatePicker 绑定使用 500ms 去抖防持久化风暴（`BillingPlanCatalog.swift`、`BillingSectionView.swift`、`AppPreferencesModel.swift`、`TotalView.swift`、`MenuBarView.swift`）。

### Changed

- **悬浮面板详细/简略模式重构**：详细模式保留完整 Liquid Glass 信息卡；简略模式改为更轻的独立表面、居中纵向结构和 54pt 圆形指标/密度符号。响应式列数改为按可用内容宽度推导，默认 480×320 下详细模式为 2 列、简略模式为 4 列，放大后最多 4 列（`BalanceFloatingPanelLayout.swift`、`BalanceProviderCardView.swift`、`BalanceMinimalProviderTile.swift`）。
- **悬浮面板 widget 状态区与动效**：顶部由窗口标题栏式 header 改为状态点、标题、刷新时间和 hover-only 圆形操作；进度条、圆环、数字与按钮反馈均显式遵循 Reduce Motion。卡片无障碍摘要改由现有本地化 key 与格式化器组装，不再直接暴露 Core 的 `shortSummary`（`BalanceFloatingPanelView.swift`、`BalanceProviderCardView.swift`、`BalanceMinimalProviderTile.swift`、`LiquidGlassButtonStyle.swift`）。
- **设置面板布局优化**：`SettingsSurfaceCard` 主卡圆角 28→18pt、副卡 22→16pt，`SettingsControlTile` padding 12→10pt，`SettingsSummaryCard` 数值字号 22→26pt，提升信息密度和视觉层次（`Components.swift`）。
- **菜单栏宽度与信息层级重构**：窗口宽度 290→320pt，header 新增月费大字（22pt bold），概览区改为月费大卡 + 3 指标行，余额区改用 `LazyVGrid adaptive(minimum:140)` + `ScrollView` 自适应，底部按钮 1 行 3 按钮布局（`MenuBarView.swift`）。
- **菜单栏字号与可访问性**：`cardBar` 字号 caption2→caption，移除固定宽度改用 maxWidth/fixedSize 自适应，`minimumScaleFactor` 0.6→0.8，sparkline 高度 44→60pt，图标按钮追加 `accessibilityLabel`（`MenuBarView.swift`）。
- **概览 Tab 2×2 布局**：summary grid 4 列→2×2，`dataSourceRow` label `frame(width:120)`→`frame(minWidth:100,maxWidth:140)`（`OverviewSectionView.swift`）。
- **偏好 Tab 主题选择器**：`HStack`→`LazyVGrid adaptive(minimum:80)`，4 主题在窄窗口下可换行（`PreferencesSectionView.swift`）。
- **余额 Tab 快照折叠**：`providerSnapshotRow` 详情（quotaWindows/valueEntries）折叠到 DisclosureGroup，摘要行始终可见；凭证按钮 `SettingsActionWrap`→`HStack+ScrollView(.horizontal)`（`BalanceSectionView.swift`）。
- **安全 Tab 信息密度**：`securityDetailRow` 去除 `SettingsControlTile` 包裹，改用普通 VStack+HStack + `settingsInsetSurface`（`SecuritySectionView.swift`）。
- **开发者 Tab 动画与折叠**：toggle 双重保障过渡动画（`withAnimation` + `.animation`），优化扫描结果 `ScrollView`→`DisclosureGroup`，governanceRow padding 统一 8pt horizontal + 4pt vertical（`DeveloperSectionView.swift`）。
- **备份 Tab 折叠优化**：概览和完备性卡片始终可见并上移，分层状态和文件列表折叠到 `DisclosureGroup`，页面高度显著降低（`BackupSectionView.swift`）。
- **其他 Tab 间距微调**：OpenCode/Codex section 间距 18→10pt，Skills 补充 helper text，Billing provider 卡片间距 10→14pt（`OpenCodeSectionView.swift`、`CodexSectionView.swift`、`SkillsSectionView.swift`、`BillingSectionView.swift`）。

### Fixed

- **菜单栏余额卡片文本截断**：`cardBar` 中 `GeometryReader` 进度条贪婪占用 HStack 剩余空间，挤压 `countdown`/`rate`/`待预估` 文本。将消耗速率/待预估从 cardBar 内移至卡片标题行右侧，并给进度条添加 `layoutPriority(-1)` 使其最后取空间。短窗口显示 `约 XX%/h`、长窗口显示 `约 XX%/d`，优先取周期最短的窗口（`MenuBarView.swift`）。
- **余额浮窗简略模式进度条被压缩为零宽度**：简略卡 64pt 宽度下，标签与百分比最小宽度之和超过 48pt 内容区，`GeometryReader` 进度条被压缩为 0pt。改为标签与百分比独占一行、进度条独占下一行全宽 48pt，并支持仅提供 `remainingRatio` 时的数据回退（`BalanceMinimalProviderTile.swift`、`BalanceFloatingPanelLayoutTests.swift`）。
- **余额浮窗简略模式改为五格离散进度条**：将连续胶囊进度条替换为 5 个分离的 Capsule 段，保留连续归一化填充（如 67% 显示为 3 满格 + 第 4 格 35% + 1 空格），移除屏幕上的百分比与预估消耗文本，VoiceOver 无障碍摘要保持不变（`BalanceMinimalProviderTile.swift`、`BalanceFloatingPanelLayoutTests.swift`）。
- **悬浮面板蓝色选中与灰色焦点框**：根因是 `.nonactivatingPanel` 仍通过 `makeKeyAndOrderFront` 成为 key/main window，且 SwiftUI 操作按钮继续参与系统焦点效果。面板改用 `orderFrontRegardless()`，`canBecomeKey`/`canBecomeMain` 均为 `false`，hosting view 关闭 AppKit focus ring；刷新/关闭按钮禁用系统 focus effect 并使用无 tint 的自定义按压反馈（`BalanceFloatingPanelCoordinator.swift`、`BalanceFloatingPanelView.swift`、`LiquidGlassButtonStyle.swift`、`BalanceFloatingPanelWindowTests.swift`）。
- **悬浮面板关闭按钮不可用**：`BalanceFloatingPanelCoordinator.close()` 通过 `panel?.performClose(nil)` 触发关闭，但 `.borderless` + `.nonactivatingPanel` 的 `NSPanel` 没有 titlebar close button，`performClose` 在此样式组合下行为不可靠，调用链无法可靠到达 `windowShouldClose`。改为直接 `panel?.orderOut(nil)` + 在 `isApplyingVisibilityChange` 守卫下写回 `balanceFloatingPanelEnabled = false`；`windowShouldClose` 保留原逻辑作为外部触发（Accessibility/脚本）的兜底防御（`BalanceFloatingPanelCoordinator.swift`）。

## [v1.0.1] - 2026-07-16

### Added

- **Ollama Cloud 缓存读估算**：对 `ollama-cloud` Provider 下标准化的 `deepseek-v4-flash` / `deepseek-v4-pro` 模型自动启用缓存读缺失估算（无需开发者模式）。基于 2026-07 观测快照计算命中率，使用 `estimatedCacheRead = input × (rate / (1−rate))` 公式估算缺失的缓存读值。缓存区卡片标题切换为"缓存（含估算）"变体，Provider 缓存行展示估算值和 `estimated` 标签，趋势图 tooltip 追加独立 `mint` 色估算行。估算值不影响计费 `actualTokens`、`cost`、`cacheSavedCost` 和源数据（`DashboardAnalytics.swift`、`DetailView.swift`）。
- **`cacheSavedCost` 计算**：新公式 `cacheRead × (inputPrice − cacheReadPrice) / 1 000 000`，基于模型定价目录中的 `input` 与 `cacheRead` 差价计算真实缓存节省费用；仅使用真实 `cacheRead`，不含估算值（`DashboardAnalytics.swift`）。
- **文档更新**：`Token统计口径定义.md` 新增 §4 Ollama Cloud 缓存读估算定义；`Provider 计费定价速查.md` 补充缓存读估算公式和 `cacheSavedCost` 公式；`开发手册.md` 更新 `DashboardAnalytics.swift` 和 `DetailView.swift` 的描述（`docs/`）。
- **TaskClassification 接线**：`TaskClassificationEngine.classify` 结果接入 DetailView 明细表行，以彩色 Capsule 标签展示（`.unclassified` 不显示）。cacheHeavy 规则对 ollama-cloud 行使用估算后的 cacheRead 判断（`TaskClassification.swift`、`DetailView.swift`）。
- **TotalView 缓存卡片标注**：当 payload 含 Ollama Cloud 估算数据时，总览页缓存 tokens 卡片 subtitle 切换为"不含 Ollama Cloud 缓存估算"（`TotalView.swift`）。
- **快照比率复核提醒**：代码注释和文档中明确标注快照观测期（2026-07）和季度复核流程（`DashboardAnalytics.swift`、`docs/Token统计口径定义.md`）。

### Changed

- **缓存区展示与数据口径分离**：`CacheSummary.cacheReadTokens` 和 `cacheHitRate` 改为含估算的展示口径；`ProviderRankRow` 和 `ModelComparisonRow` 保持真实 `actualTokens` 不变；`cacheSavedCost` 仅基于真实 `cacheRead`（`DashboardAnalytics.swift`）。
- **余额刷新哨兵重构**：超时哨兵不再作为 `withTaskGroup` 的常规子任务等待 45s，改为 sentinel + 计数模式 — 所有真实 provider 完成后立即 `cancelAll()` 取消哨兵，`refresh()` 不再强制等待 45s（`BalanceManager.swift`）。
- **令牌读取异步化**：`AuthTokenProvider.token(for:)` 包装在 `Task.detached` 中，避免阻塞主线程（`BalanceManager.swift`）。
- **合并 snapshots 发布**：排序结果与消费率计算后的赋值合并为单次 `@Published` 赋值，每个刷新周期 SwiftUI 重绘从 7 次减少到 6 次（`BalanceManager.swift`）。
- **菜单栏布局重组**：设置和退出按钮改为图标形式（`gearshape`、`xmark.circle`），底部 HStack 排列；保留独立的「打开主窗口」和「刷新全部」文本按钮（`MenuBarView.swift`）。
- **余额卡片统一高度**：菜单栏余额卡片强制 `minHeight: 88`，避免不同 provider 数据量不同导致卡片高度不齐（`MenuBarView.swift`）。
- **后台刷新调度器脱离主线程**：`BalanceRefreshScheduler.start()` 改为 `Task.detached(priority: .medium)`，偏好读取通过 `MainActor.run` 跳转，防止 App Nap 并降低主线程占用（`BalanceRefreshScheduler.swift`）。
- **Dock 图标同步移除魔法数字**：`syncDockPolicyAfterWindowClose` 从 `Task.sleep(50ms)` 改为 `DispatchQueue.main.async`，消除竞态窗口（`WindowLifecycleManager.swift`）。
- **主窗口场景从 `WindowGroup` 改为 `Window`**：`TokenCostApp.swift` 主场景从 `WindowGroup(id: "main")` 改为 `Window(id: "main")`，由系统保证单窗口实例；`openWindow(id: "main")` 在窗口已打开时自动前置，已关闭时重新打开（`TokenCostApp.swift`）。
- **`WindowOpeningSupport` 简化为统一入口**：移除 `showOrRevealMainWindow`、`openSingletonWindow`、`pendingWindowIDs` 去重逻辑和 `windowDidOpen` 桥接，改为单一 `openWindow(id:openWindow:)` 函数，仅设置激活策略后调用 SwiftUI `openWindow(id:)`（`WindowOpeningSupport.swift`、`WindowLifecycleManager.swift`）。
- **余额标题行合并刷新图标**：`balanceSummary` 标题行右侧新增 `arrow.clockwise` 刷新按钮，刷新中显示 spinner，移除底部独立刷新 HStack（`MenuBarView.swift`）。

### Fixed

- **Ollama Cloud 缓存命中率始终为 0**：Ollama Cloud 代理的 DeepSeek 模型不返回 `cacheRead`，导致缓存区无法反映真实缓存效率。新增估算填补展示空白，`cacheHitRate` 从 0% 恢复至接近官方 API 的 ~92%（Flash）/ ~95%（Pro）展示口径（`DashboardAnalytics.swift`）。
- **余额刷新强制 45s 最短时间**：哨兵任务 `Task.sleep(45s)` 作为 `withTaskGroup` 子任务导致 `for await` 必须等待所有子任务（含哨兵）完成才退出，即使所有 provider 在 200ms 内响应也需等满 45s。重构为 sentinel + 计数模式，所有 provider 完成后立即取消哨兵（`BalanceManager.swift`）。
- **取消时数据损坏**：哨兵的 `CancellationError` 被捕获后返回 `BalanceSnapshot.unavailable(.opencodeGo, ...)`，通过 `upsertSnapshot()` 覆盖真实的 `.opencodeGo` 结果。改为返回 `nil`，不再生成虚假快照（`BalanceManager.swift`）。
- **ForEach ID 非唯一导致崩溃风险**：`BalanceQuotaWindow.id` 使用 `label` 字段、`BalanceValueEntry.id` 使用 `"\(label)-\(currencyCode)"`，当两个窗口/条目有相同标签时触发 SwiftUI ForEach 运行时崩溃。改为加入 `windowSeconds` / `amount` 字段保证唯一性（`BalanceModels.swift`）。
- **窗口单例守卫缺失**：`openSingletonWindow` 无 `NSApp.windows` 已存在检查，重复调用会创建多个窗口；`showOrRevealMainWindow` 未检查 `$0.isVisible`，已隐藏窗口不会被 reveal。两处均新增可见性守卫（`WindowOpeningSupport.swift`）。
- **禁用 provider 后 goLastDiagnosis 过时**：`rebuildCheckers()` 移除禁用 provider 的快照但未清除对应诊断，导致 UI 显示已禁用 provider 的错误。新增 `.opencodeGo` 禁用时清除诊断（`BalanceManager.swift`）。
- **Dock 图标同步竞态**：`WindowLifecycleManager.syncDockPolicyAfterWindowClose` 使用 `Task.sleep(50ms)` 延迟同步 Dock 策略，魔法数字 50ms 在窗口关闭动画时长不同时可能竞态。改为 `DispatchQueue.main.async` 在下一个 run loop 执行同步（`WindowLifecycleManager.swift`）。

## [v1.0.0] - 2026-07-10

> 相对 `v0.9.9` 的累计变更。**正式版发布**：凭证系统从 Keychain 全面迁移至本地 AES-256-GCM 加密存储，启动时自动凭证引导，DetailView 异步加载性能优化。

### Added

- **本地加密凭证存储**：新增 `LocalEncryptedCredentialStore`（CryptoKit AES-256-GCM），密文 JSON + 独立 32 字节随机密钥文件分离存储；目录权限 0700 / 文件权限 0600，原子写入，每次写入使用全新随机 nonce（`LocalEncryptedCredentialStore.swift`、`LocalCredentialService.swift`）。
- **凭证自动引导**：`CredentialBootstrapService` 在 App 启动时自动从浏览器解密 OpenCode Go 和 Ollama 凭证，最多重试 3 次（间隔 1 秒）；成功后缓存到内存，best-effort 写入 Keychain（不触发授权弹窗）；3 次失败后回退 Keychain 已有凭证。用户可在设置中切换为「仅从 Keychain 读取」模式（`CredentialBootstrapService.swift`、`ContentView.swift`）。
- **凭证来源模式切换**：设置页余额区新增「凭证来源模式」Picker，支持 `autoBrowser`（启动时自动浏览器解密）和 `keychainOnly`（仅从 Keychain 读取）；切换时清除内存缓存（`BalanceSectionView.swift`、`AppPreferences.swift`、`AppPreferencesModel.swift`）。
- **旧 Keychain 显式导入**：设置页余额区新增「导入旧 Keychain」确认对话框，将旧 macOS Keychain 中缺失的 Go 或 Ollama 凭证复制到本地加密存储，不删除 Keychain 记录（`BalanceSectionView.swift`、`LocalCredentialService.swift`）。
- **AppPreferencesModel 凭证操作集中化**：新增 `saveLocalGoCredentials()`、`clearLocalGoCookiePreservingWorkspaceID()`、`saveLocalOllamaCookie()`、`clearLocalOllamaCookie()`，所有凭证读写统一通过 `LocalCredentialService` + `CredentialBootstrapService` 双写，消除 UI 层直接操作 Keychain 的散落代码（`AppPreferencesModel.swift`）。
- **本地化新增 key**：新增 `settings.balance.credentialSource`、`settings.balance.importLegacyKeychain.*`、`balance.bootstrap.error.title` 等 8 个中英双语本地化键（`Localizable.strings` 中英双语）。
- **凭证系统测试覆盖**：新增 `LocalEncryptedCredentialStoreTests`、`LocalCredentialServiceTests`、`CredentialBootstrapServiceTests` 覆盖加密存储 round-trip、凭证 CRUD、浏览器/Keychain 双来源引导等边界场景（`Tests/`）。

### Changed

- **凭证存储从 Keychain 全面迁移至本地加密存储**：Go workspace ID / Go auth cookie / Ollama cookie 从 `SecureCredentialStore`（macOS Keychain）迁移至 `LocalEncryptedCredentialStore`（AES-256-GCM）；`SecureCredentialStore` 降级为仅作为显式 legacy 导入源，默认运行时不调用（`SecureCredentialStore.swift`、`AuthTokenProvider.swift`、`OpenCodeGoBalanceProvider.swift`、`CodexBalanceProvider.swift`、`BalanceManager.swift`）。
- **UI 凭证文案更新**：所有「已保存到 Keychain」改为「已本地保存」；浏览器导入确认弹窗移除 Keychain 授权提示；Ollama 凭证区标题从「通过 Keychain 存储」改为「存储到本地加密存储」（`Localizable.strings` 中英双语、`BalanceSectionView.swift`）。
- **BalanceSectionView UI 重构**：凭证卡片从独立常驻卡片改为放在 Provider toggle 行后的可折叠区域（重构已存在的折叠逻辑），新增凭证来源模式切换控件（`BalanceSectionView.swift`）。
- **DetailView analytics 异步加载**：`cachedAnalytics` 计算从 `.onAppear` 同步阻塞改为 `Task.detached(priority: .userInitiated)` 异步计算，新增 `analyticsLoadingCard` 加载占位态，避免大数据 payload 时主线程卡顿（`DetailView.swift`）。
- **OpenCode Go workspaceID 绑定从 AppPreferences 直读改为本地凭证存储优先**：`opencodeGoWorkspaceIDBinding` 优先读取 `LocalCredentialService` 中的值，回退到 `preferences.opencodeGoWorkspaceID`（`AppPreferencesModel.swift`）。
- **文档同步更新**：开发手册 §3.1 新增 `LocalEncryptedCredentialStore` / `LocalCredentialService` / `SecureCredentialStore` 文件描述，§8 安全边界新增本地加密存储说明；架构逻辑链图关键文件索引同步更新（`docs/开发手册.md`、`docs/架构逻辑链图.md`）。

### Removed

- **Keychain 运行时依赖**：默认运行时不再自动访问 macOS Keychain，避免本地构建 app 触发系统授权弹窗；旧 Keychain 凭证需通过设置页「导入旧 Keychain」显式迁移（`SecureCredentialStore.swift`、`BalanceManager.swift`、`BrowserCookieExtractor.swift`）。

### Fixed

- **OpenCode Go workspaceID 保存后未同步到运行时凭证发现链路**：`saveLocalGoCredentials` 双写 `LocalCredentialService` + `CredentialBootstrapService.updateCachedGoCookie`，消除 UI 保存后刷新仍使用旧 Keychain 值的问题（`AppPreferencesModel.swift`）。
- **BalanceRefreshScheduler 轮询缺乏注释**：新增 10s 轮询间隔设计说明，明确 `shouldRefresh()` guard 防止不必要的刷新调用（`BalanceRefreshScheduler.swift`）。
- **OpenCodeGoBalanceProvider credential 发现链路**：从 `SecureCredentialStore` 改为 `LocalCredentialService`，消除 Keychain 不存在时凭证发现静默失败（`OpenCodeGoBalanceProvider.swift`、`BalanceManager.swift`）。

### Security

- **凭证存储升级为 AES-256-GCM**：本地加密凭证存储使用 CryptoKit 实现，密文与密钥文件分离，目录/文件权限严格限制，原子写入 + 每次全新 nonce（`LocalEncryptedCredentialStore.swift`）。
- **启动时凭证自动引导安全边界**：浏览器自动解密最多重试 3 次，失败后静默回退 Keychain，不阻塞 App 启动；凭证仅驻留内存，不写入日志或文件（`CredentialBootstrapService.swift`）。
- **凭证来源模式门控**：`keychainOnly` 模式完全禁用浏览器自动解密，仅从 Keychain 读取已有凭证（`AppPreferences.swift`、`CredentialBootstrapService.swift`）。
- **旧 Keychain 凭证导入确认**：需用户显式在设置页确认后才执行导入，不自动迁移（`BalanceSectionView.swift`）。

## [v0.9.9] - 2026-07-07

> 相对 `v0.9.8` 的累计变更。

### Added

- **开发者模式强制更新（§2.5 例外）**：Developer Mode 设置页新增「强制更新」section，在开发者模式启用后可见；提供 toggle 启用强制更新、一键下载最新 GitHub release、进度显示和下载完成后的打开按钮。该功能作为开发者模式治理规范 §2.5 记录的联网边界例外，仅手动触发（`DeveloperModePreferences.forceUpdateFromGitHub`、`UpdateCheckerModel.forceDownloadLatest()`、`DeveloperSectionView.swift`）。
- **余额自定义排序**：`AppPreferences` 新增 `balanceCustomOrder: [BalanceProviderKind]` 和 `balanceOrderLocked: Bool` 两个字段；`AppPreferencesModel` 新增 `sortBalanceSnapshots(_:)` 统一排序方法（自定义顺序 → fallback `balanceSortOrder`）和 `resetBalanceCustomOrder()` 复位方法。设置页余额区新增「余额排序」卡片，解锁后可拖拽重排所有 Provider（`List.onMove`），锁定后恢复固定顺序；余额总览卡片 `BalanceOverviewCard` 在解锁状态下支持行拖拽排序（`BalanceSectionView.swift`、`BalanceOverviewCard.swift`、`AppPreferencesModel.swift`）。
- **OpenCode 详情页 Ollama 余额展示**：`DetailView` 的 `BalanceOverviewCard` 过滤器在开发者模式启用且 `ollamaUsageTrackingEnabled` 为 true 时，额外包含 `.ollama` 快照；不注入伪造快照，仅使用 `BalanceManager` 已有真实/不可用快照（`DetailView.swift`）。

### Changed

- **余额排序逻辑集中化**：`MenuBarView` 的 `sortedSnapshots` 计算属性从内联排序改用 `appPreferencesModel.sortBalanceSnapshots(_:)`，确保菜单栏与总览页使用同一排序逻辑（`MenuBarView.swift`）。
- **BalanceOverviewCard 签名扩展**：新增 `@ObservedObject var appPreferencesModel: AppPreferencesModel` 参数，三个调用点（`DetailView`、`CodexPageView`、`TotalView`）均已更新；`CodexPageView` 同步新增 `appPreferencesModel` 注入（`BalanceOverviewCard.swift`、`DetailView.swift`、`CodexPageView.swift`、`TotalView.swift`、`ContentView.swift`）。
- **DeveloperSectionView 新增 UpdateCheckerModel 依赖**：`DeveloperSectionView` 和 `SettingsView` 新增 `@ObservedObject var updateCheckerModel: UpdateCheckerModel`，由 `TokenCostApp` 在 `Window("Settings")` 中注入（`DeveloperSectionView.swift`、`SettingsView.swift`、`TokenCostApp.swift`）。

### Fixed

- **余额总览卡片硬编码中文**：`BalanceOverviewCard` 空状态标题/副标题/正文、不可用行标签、赠款文案均改用 `AppLocalization` 本地化键；赠款文案复用现有 `balance.value.grantedShort` 键避免重复；`lastRefreshTime` 改用新增的 `TokenCostFormatters.localDateTime(_ date: Date)` 重载，消除冗余 `ISO8601DateFormatter` 实例化（`BalanceOverviewCard.swift`、`Components.swift`、`Localizable.strings`）。
- **更新检查器硬编码英文**：`UpdateCheckerModel` 的 `startDownload` 和 `openDownloadedApp` 错误消息改用本地化键；`forceDownloadLatest` catch 分支从泛化本地化键改为 `error.localizedDescription`，与 `startDownload` catch 分支保持一致（`UpdateCheckerModel.swift`、`Localizable.strings`）。
- **TokenCostFormatters formatter 复用**：`localDateTime(_:)` 的 `ISO8601DateFormatter` 和 `DateFormatter` 从每次调用创建改为 `static let` 单例复用，新增 `localDateTime(_ date: Date)` 重载（`Components.swift`）。
- **余额总览卡片拖拽排序越界崩溃**：`BalanceOverviewCard` 的 `.onMove` 回调中 `order` 取自持久化的 `balanceCustomOrder`（可能短于 `availableSnapshots`），导致 SwiftUI 传入的 `offsets`/`target` 索引越界触发 `Array swapAt` 断言崩溃。改为从 `availableSnapshots.map(\.provider)` 构造 `order`，保证与 `ForEach` 索引空间一致；同时 `AppPreferencesModel` 集中规范化 `balanceCustomOrder`，对重复 provider 去重、补齐缺失 provider，并在总览卡过滤列表拖拽时保留隐藏/不可用 provider 的相对顺序，避免自定义排序被截断；设置页排序列表复用同一规范化逻辑，防止重复 `ForEach` ID。新增 4 个回归测试（`BalanceOverviewCard.swift`、`BalanceSectionView.swift`、`AppPreferencesModel.swift`、`AppPreferencesModelTests.swift`）。

### Developer Mode Exception (§2.5)

- 开发者模式治理规范新增 §2.5，记录强制更新功能的联网边界例外：仅当用户手动在 Developer Mode 中切换 toggle 并点击「下载」按钮时触发网络请求，不走自动/隐式更新检查路径。该入口技术上不触发 `developer_mode_sources.manifest` 的 banned-symbol 扫描，但治理上仍作为 Developer Mode UI 的网络边界例外记录。

## [v0.9.8] - 2026-07-06

> 相对 `v0.9.7` 的累计变更。

### Added

- **菜单栏余额显示模式设置入口**：余额监控设置新增「菜单栏余额显示模式」分段控件，可在已使用 / 剩余额度口径间切换；该设置仅影响菜单栏余额卡片颜色和百分比，不改变总览页与设置页原始已用百分比显示（`BalanceSectionView.swift`、`MenuBarView.swift`、`Localizable.strings`）。
- **应用生命周期级余额刷新调度器**：新增 `BalanceRefreshScheduler`，在主窗口关闭后仍按既有 `balanceEnabled`、刷新间隔、`BalanceManager` backoff 与 `isRefreshing` 守卫刷新余额（`BalanceRefreshScheduler.swift`、`TokenCostApp.swift`）。

### Changed

- **计费与开发者文档改为独立窗口**：`PricingDocView` 与 `DeveloperModeDocView` 从设置页 sheet 改为 `Window` scene，可独立移动并与设置窗口并行使用（`TokenCostApp.swift`、`SettingsView.swift`、`BillingSectionView.swift`、`DeveloperSectionView.swift`）。
- **窗口生命周期策略改为实际窗口同步**：窗口关闭后基于 `NSApp.windows` 的可见用户窗口同步 Dock 图标策略，并追踪窗口成为 key 的事件以覆盖运行时打开的 settings/doc 窗口（`WindowLifecycleManager.swift`、`AppDelegate.swift`）。

### Fixed

- **主窗口重复创建风险**：`Cmd+1` 与菜单栏「打开主窗口」统一使用 `showOrRevealMainWindow`，优先前置已有主窗口，仅在不存在时对 `WindowGroup(id: "main")` 调用 `openWindow`；同时移除 `Notification.Name.openMainWindow` 中转链路（`WindowOpeningSupport.swift`、`TokenCostCommands.swift`、`MenuBarView.swift`、`TokenCostApp.swift`、`AppDelegate.swift`）。
- **设置窗口 API 语义不一致**：`ContentView` 与菜单栏设置入口从 `openSettings()` 改为 `openWindow(id: "settings")`，匹配项目实际使用的 `Window("Settings", id: "settings")` scene（`ContentView.swift`、`MenuBarView.swift`）。
- **短时间窗口消费速率异常放大**：`ConsumptionRateCalculator` 对线性回归与 fallback 路径均要求至少 300 秒有效跨度，并将速率上限限制为 200%/h，避免短窗口显示数千百分比每小时；新增 3 个边界测试（`ConsumptionRateCalculator.swift`、`CodexTokenCostCoreTests.swift`）。

## [v0.9.7] - 2026-07-03

> 相对 `v0.9.6` 的累计变更。

### Added

- **Ollama Cloud 用量监控与计费方案**：余额监控系统新增 Ollama Cloud 作为第 5 个 Provider；门控在开发者模式下，默认关闭；使用 ephemeral URLSession，cookie 不持久化、不打印、不上传（`OllamaBalanceProvider.swift`、`AuthTokenProvider.swift`、`BalanceModels.swift`、`BalanceManager.swift`、`DeveloperModePreferences.swift`）。计费系统新增 `Ollama Cloud` 作为第 6 个 BillingProvider，含 Free $0 / Pro $20/月 / Max $100/月 三个预设档位（`BillingPlanCatalog.swift`）
- **Ollama session cookie 迁移至 Keychain**：Ollama 凭证从 `~/.config/ollama-quota/cookie` 文件读取迁移至系统 Keychain，通过 `SecureCredentialStore` 统一管理；新增 `saveOllamaCookie()` / `getOllamaCookie()` / `deleteOllamaCookie()` 方法，同时保留对裸 cookie 值和完整 `Cookie:` header 格式的向后兼容解析（`SecureCredentialStore.swift`、`AuthTokenProvider.swift`）
- **Ollama 浏览器 Cookie 自动提取**：`BrowserCookieExtractor` 新增 `extractOllamaCookie()` 方法，从 Chrome / Edge / Brave / Arc 的 Chromium cookies SQLite 数据库中搜索 `ollama.com` 的 session cookie，优先读取明文 `value` 列，回退 AES-CBC 解密 `encrypted_value`；支持最新的 `Network/Cookies` 路径和传统 `Cookies` 路径（`BrowserCookieExtractor.swift`）
- **Ollama 余额 Keychain 与浏览器提取测试覆盖**：新增 12 个测试用例覆盖 Keychain 隔离（UUID 独立 service 的 save/get/delete round-trip、跨 account 独立性、跨 service 独立性）、AuthTokenProvider Keychain 读取（空 Keychain 返回 nil、裸 cookie 值归一化为 `auth=`、完整 `name=value` header 保留、`Cookie:` 前缀剥离、分号路径截断）、以及 BrowserCookieExtractor SQLite 查询（匹配 ollama.com 域名、无匹配返回 nil、跳过空值）（`CodexTokenCostCoreTests.swift`）
- **余额凭证卡片折叠重构**：OpenCode Go 和 Ollama Cloud 的凭证输入区从独立常驻卡片改为放在各自 Provider toggle 行后的可折叠区域，默认收起，点击钥匙图标展开，减少设置页视觉噪声（`BalanceSectionView.swift`）
- **Ollama Cloud 5 小时 / 每周限额窗口解析**：`OllamaBalanceProvider` 新增 `aria-label="Session usage NN%"` 和 `aria-label="Weekly usage NN%"` 正则提取，解析 `data-time` ISO 8601 重置时间戳，构建双 `BalanceQuotaWindow`（5 小时 + 7 天）对齐 Codex 的 rate limit 展示能力；保留旧三重降级 fallback 应对 HTML 结构变更；新增 `balance.ollama.window.session` / `balance.ollama.window.weekly` 本地化 key（中英双语）（`OllamaBalanceProvider.swift`、`Localizable.strings`）
- **余额窗口去重显示**：`BalanceSectionView` 的 `quotaWindows` 遍历新增去重逻辑，跳过与 `primaryWindowLabel` / `secondaryWindowLabel` / `tertiaryWindowLabel` 重复的条目，同时为 `quotaWindows` 增加 `resetAt` 时间显示；此修复惠及 Codex 和 Ollama 两个 Provider（`BalanceSectionView.swift`）
- **余额消耗速率功能**：从 v0.9.5 分支移植 `ConsumptionRateCalculator`，基于历史快照的线性回归估算配额消耗速率（%/h、%/d），支持 fallback 窗口内估算和置信度输出；`BalanceManager.refresh()` 每次刷新后自动计算并存储采样（`ConsumptionRateCalculator.swift`、`BalanceModels.swift`、`BalanceManager.swift`）
- **余额用量预估显性占位**：当消耗速率样本不足时，`BalanceOverviewCard` 和 `MenuBarView` 的配额窗口进度条下方显示「待预估」占位文字，替代此前默默不显示的行为（`BalanceOverviewCard.swift`、`MenuBarView.swift`）
- **余额统一日志系统**：新增 `BalanceLog` 基于 `os.Logger` 的分级日志（debug/info/notice/error/fault），覆盖刷新、速率计算、窗口重置、Provider 错误等关键事件，替代零散的 `#if DEBUG print`（`BalanceLog.swift`、`BalanceManager.swift`、`ConsumptionRateCalculator.swift`）
- **菜单栏余额卡片网格**：`MenuBarView` 余额区从垂直列表改为 `LazyVGrid` 双列卡片布局，支持 `balanceSortOrder`（配额优先/余额优先/按 Provider）和 `balanceDisplayMode`（已用/剩余）偏好设置（`MenuBarView.swift`、`AppPreferences.swift`、`AppPreferencesModel.swift`）
- **Ollama Plan 名称解析**：从 HTML 中 `Cloud usage` 标签后的 `<span>` 提取 plan 名称（free/pro/max），写入 `BalanceSnapshot.planType`（`OllamaBalanceProvider.swift`）
- **Ollama 解析失败日志改用 BalanceLog.notice**：不再 `#if DEBUG print`，改为统一 `BalanceLog.provider.notice`，且不输出 HTML 原文，仅输出长度（`OllamaBalanceProvider.swift`）

### Changed

- **Ollama cookie 存储方式**：从文件存储 `~/.config/ollama-quota/cookie` 改为系统 Keychain，配置入口从手动放置文件改为设置页可折叠凭证区 + 浏览器自动导入。README 已更新移除文件路径引用，改为 Keychain 和浏览器导入描述（`README.md`）

### Removed

- **Ollama 旧文件回退**：移除 `AuthTokenProvider.readOllamaCookie()` 中读取 `~/.config/ollama-quota/cookie` 的文件回退逻辑，所有 Ollama 凭证读取现仅通过 Keychain。已废弃的 `ollamaCookieURL` 属性保留标记为 `@available(*, deprecated)` 以兼容外部 UI 引用（`AuthTokenProvider.swift`）

### Fixed

- **余额监控空 Provider 时 backoff 误递增**：`BalanceManager.refresh()` 在 `checkers` 为空时不再执行 task group，避免 `consecutiveFailures` 无限递增导致后续刷新被永久阻塞（`BalanceManager.swift`）
- **余额 Provider 默认启用逻辑**：`BalanceSectionView` 中 Provider toggle 的默认值从硬编码 `kind != .deepseek` 改为查询 `BalanceConfiguration()` 默认列表，新增 Provider 不再被错误默认启用（`BalanceSectionView.swift`）
- **Ollama Keychain 写入静默失败**：`SecureCredentialStore` 中 Ollama 专用 Keychain CRUD 使用 `kSecUseDataProtectionKeychain: true`（DPK domain），在未启用 FileVault 或无 entitlements 的 Mac 上 `SecItemAdd` 静默失败但 UI 仍显示「已保存」。已移除 DPK flag，统一使用 file-based Keychain domain（与 OpenCode Go 凭证一致），并保留 legacy DPK 只读迁移以兼容旧用户数据（`SecureCredentialStore.swift`）
- **Ollama cookie 保存状态 UI 误报**：`saveOllamaCookie` 返回 `Bool`，手动输入和浏览器导入后 UI 根据返回值设置 `ollamaCookieSaved`，保存失败时不再显示「已保存到 Keychain」（`SecureCredentialStore.swift`、`BalanceSectionView.swift`、`SettingsView.swift`）
- **Ollama Cookie header 过度截断**：`normalizeOllamaCookieHeader` 此前只保留第一个 `name=value` pair，丢失 `session`/`csrf` 等多 cookie。已改为保留所有 `name=value` pair，仅剥离 `path`/`domain`/`expires`/`max-age`/`samesite`/`secure`/`httponly`/`priority` 等 Set-Cookie 属性（`AuthTokenProvider.swift`）
- **OllamaBalanceProvider 错误消息硬编码中文**：9 条 provider 级别错误消息全部替换为 `AppLocalization.text()` 调用，新增 `balance.ollama.error.*` 命名空间 key（中英双语）（`OllamaBalanceProvider.swift`、`Localizable.strings`）
- **BalanceSectionView 重复 onAppear**：`ollamaCredentialInputArea` 上的 `.onAppear` 与 `SettingsView` 的 `.onAppear` 重复读取 Keychain cookie，已移除 `BalanceSectionView` 中的重复（`BalanceSectionView.swift`）
- **Ollama HTML 正则无法匹配 `used` 后缀**：`aria-label="Session usage 51% used"` 中的 ` used` 后缀导致 Strategy 1 正则 `%"` 静默失败，降级为 Strategy 4 单窗口模式（丢失 Weekly 窗口和时间戳）。已修正正则为 `%[^"]*"` 允许 `%` 与 `"` 间有任意非引号字符，同时保持对旧格式 `aria-label="Session usage 51%"` 的向后兼容（`OllamaBalanceProvider.swift`）

## [v0.9.6] - 2026-06-30

> 相对 `v0.9.2` 的累计变更。

### Changed

- **菜单栏弹窗布局优化**：header 改为状态指示器（圆点+简短标签+tooltip），删除冗余数据源 block；balance 区 miniBar 弹性宽度适配多窗口场景（`MenuBarView.swift`）
- **CodexSessionModel 来源发现重构**：移除内联的 `buildDiscoverySources()` 和 `refreshDiscoverySources()` 方法（约 300 行），来源发现逻辑统一由 `SourceDiscoveryService` 管理；新增扫描深度（1-12）和候选数（1-1000）边界校验；扫描根和手动路径增加 `isSafeScanRoot` 安全过滤（`CodexSessionModel.swift`）
- **CodexSessionCollector 分块读取重构**：从 `readDataToEndOfFile` 全量读取改为 1MB 分块逐行扫描，支持超大 JSONL 文件；移除 `SessionLine` Codable 类型解码，统一使用 `JSONSerialization` 处理；新增 32MB 单行上限和超长行跳过警告；`ISO8601DateFormatter` 改为 static 单例避免重复创建（`CodexSessionCollector.swift`）
- **SHA256 实现替换**：`BackupService` 中约 80 行自定义 SHA256 实现替换为 `CryptoKit.SHA256`；`performFullLayeredBackup` 新增 `backupLock`（`OSAllocatedUnfairLock`）线程安全保护（`BackupService.swift`）
- **本地化语言切换线程安全**：`AppLocalization.currentLanguage` 从裸 `nonisolated(unsafe)` 改为 `OSAllocatedUnfairLock` 保护读写，消除 data race 风险（`Localization.swift`）
- **余额刷新间隔支持秒级**：设置页余额刷新间隔新增秒级选项（`settings.balance.refreshIntervalSeconds`），支持更灵活的刷新频率（`BalanceSectionView.swift`、`Localizable.strings` 中英双语）
- **总计页 Token 口径文案统一**：`overview.openCode.actualTokens` 和 `overview.summary.totalActualTokens` 从中英双语更新为「实际 Token / Actual Tokens」，subtitle 明确标注「输入+输出+推理，不含缓存」（`Localizable.strings` 中英双语）
- **CI 升级至 macOS 26**：GitHub Actions runner 从 matrix 构建（macos-14/15）升级为单一 `macos-26`，适配 Liquid Glass SDK（`.github/workflows/ci.yml`）

### Fixed

- **Codex JSONL 长行误判不兼容**：`CodexSessionDiscoveryService` 的 Codex 文件探针从固定 4KB 预读改为有界分块逐行扫描，支持首个有效 JSONL 行超过 4KB、前导空行和坏行跳过，并将可读但无有效 JSON dictionary 的文件正确标记为 unsupported schema（`CodexSessionDiscoveryService.swift`）
- **总计页日期格式化时区问题**：`TotalView` 中日期格式化器未设置 `timeZone`，可能导致 UTC 日期边界偏移；已显式设置为 `TimeZone(secondsFromGMT: 0)`（`TotalView.swift`）

### Security

- **SQL 注入防护**：`TokenDatabaseClient.buildUsageQuery()` 新增 `allowedSqlIdentifiers` 白名单（11 个合法列名）和 `isValidSqlIdentifierList()` 校验，拒绝非白名单列名和非法排序方向（`ASC`/`DESC` 以外），无效输入返回空结果集并触发 `assertionFailure`（`TokenDatabaseClient.swift`）
- **扫描根安全白名单**：`PathUtilities` 新增 `forbiddenScanRoots`（`/`、`/System`、`/Users`、`/Applications`、`/Library`、`/private`、`/.Trash`）和 `isSafeScanRoot()` 方法；`CodexSessionModel` 在规范化来源路径时自动过滤禁止的扫描根（`PathUtilities.swift`、`CodexSessionModel.swift`）

### Added

- **Codex 模型分布本地化**：新增 `codex.models.*` 命名空间 key（中英双语），为 Codex 页面模型分布视图提供本地化支持（`Localizable.strings` 中英双语）
- **Codex JSONL 探针测试覆盖**：新增 5 个测试用例覆盖首行超 4KB、前导空行跳过、无效首行后有效、全无效拒绝、超长行跳过等边界场景（`CodexTokenCostCoreTests.swift`）

## [v0.9.2] - 2026-06-12

> 相对 `v0.9.1` 的累计变更。

### Removed

- **删除退役空目录**：移除 `.memory/` 和 `.sisyphus/` 空目录（`AppPaths.swift`）
- **删除废弃源文件**：移除 `CodexBilling.swift` 和 `CodexSessionPaths.swift`，两个文件均为零引用死代码
- **删除未使用的 @Published 属性**：移除 `AppPreferencesModel.showBakViewer`，该属性从未被任何 View 观察

### Fixed

- **ChatGPT Plus 遗留价格冲突**：`DashboardAnalytics` 中 `legacyFallbackMonthlyCosts` 的 `openai` 值从 `$19.99` 修正为 `$20.00`，与 `BillingPlanCatalog` 对齐
- **汇率常量重复定义**：`BillingPlanCatalog.exchangeRateUSDToCNY` 改为引用 `TokenCostCurrencyService.defaultExchangeRateUSDToCNY`，消除双源不一致风险

### Changed

- **本地化调用统一**：`SecuritySectionView` 中的私有 `String.localized` 扩展替换为全局 `AppLocalization.text()`，与项目其余 300+ 处保持一致
- **版本清单补全**：`release/versions.json` 补充 v0.8.5、v0.9.0、v0.9.1 三个缺失版本记录

## [v0.9.1] - 2026-06-11

> 相对 `v0.9.0` 的累计变更。

### Added

- **备份管理功能**：新增「备份管理」设置 Tab，整合两大功能模块（`BackupPreferences.swift`、`BackupService.swift`、`BackupSectionView.swift`、`AppPreferencesModel.swift`）
  - **配置文件备份**：支持分别备份 `opencode.json`、`oh-my-openagent.json` 等 OpenCode 配置文件到外部备份目录；检测并管理 `~/.config/opencode/` 下未纳入外部备份的 `.bak` 文件，通过废纸篓安全清理（需用户显式确认）
  - **外部备份管理**：支持自定义备份目录（默认 `~/Documents/Opencode project/记忆备份/`）、自动备份（每小时/每天/每周）、自动清理（保留 N 份）、手动备份/清理按钮、备份文件列表浏览与逐条删除、备份内容概览（文件数/大小/最后备份时间）、完备性测验（应备份文件清单覆盖率）
  - 备份操作通过 `SafeFileStore` 写入外部目录、通过 `FileManager.trashItem` 安全清理 `.bak` 文件；不新增网络调用

### Changed

- **Skills 页面简化**：移除 Skills Overview 中的「Backup Manager」只读卡片，备份管理功能已迁移至独立的设置 Tab（`OpenCodeSkillsPageView.swift`）

### Fixed

- **完备性测验显示全部为"未备份"**：`verifyCompleteness()` 此前只检查扁平文件（flat）备份记录，忽略分层目录（layered `backup-*` 目录）备份。现已改为同时扫描最新分层备份的 `config-snapshot/` 和 `global-entry/` 子目录，与扁平备份合并判断完备性（`BackupService.swift`）
- **分层备份 config-snapshot 遗漏文件**：`backupConfigSnapshotLayer()` 此前只备份 `AGENTS.md`、`oh-my-openagent.json`、`opencode.json` 三个文件，现已改为备份 `allKnownConfigFiles` 中全部存在的配置文件，补齐 `opencode.jsonc`、`oh-my-openagent.jsonc`、`oh-my-opencode.json`、`oh-my-opencode.jsonc`、`openpets.md`
- **openpets.md 未纳入备份配置清单**：`allKnownConfigFiles` 此前未包含 `openpets.md`，导致该文件既不参与完备性检查，也不在分层备份的 config-snapshot 中。现已补齐，并在 `configFileGroups` 的 `agents` 分组中展示

### Security

- **备份管理安全边界**：备份写入仅通过 `SafeFileStore` 操作外部备份目录；`.bak` 文件清理使用 `FileManager.trashItem` 移至废纸篓而非永久删除，每次清理需用户显式确认；源配置文件读取为只读操作，不修改 `~/.config/opencode/` 中任何原始文件；自动备份使用本地 Timer，不新增网络请求

## [v0.9.0] - 2026-06-09

### Added

- **分层备份可配置内容层**：`BackupPreferences.enabledLayers` 控制 7 个备份层（globalEntry/globalMemory/commandsSnapshot/configSnapshot/skillsSnapshot/scripts/launchd）的启用状态，设置页提供 Toggle 列表选择（`BackupPreferences.swift`、`BackupService.swift`、`BackupSectionView.swift`、`AppPreferencesModel.swift`）
- **Skills 面板完整中文本地化**：新增 47 个 `skills.*` 命名空间 key，覆盖标题、筛选器、分区、详情、权限、诊断等全部 UI 文本（`Resources/zh-Hans.lproj/Localizable.strings`、`Resources/en.lproj/Localizable.strings`、`OpenCodeSkillsPageView.swift`）
- **开发者模式设置视图**：新建 `DeveloperSectionView.swift`，包含存储优化扫描（调用 `OptimizeScanner.scan()` 并展示结果）、本地治理视图、AI 分析占位（`DeveloperSectionView.swift`）
- **设置分区视图完整实现**：8 个设置分区视图（Overview/Preferences/Billing/Balance/OpenCode/Codex/Skills/Security）从空壳 stub 重建为完整功能 UI，包含实际控件（Toggle/Picker/Stepper/TextField）、数据绑定、分页、状态指示（`Sources/CodexTokenCostApp/Views/Settings/`）
- **MiMo 中国区年付方案**：新增 Lite/Standard/Pro/Max 四档中国区年付（¥411.84-¥6959.04/年），并新增 `mimoAnnualCN()` helper（`BillingPlanCatalog.swift`）

### Fixed

- **BAK 文件移除后选中状态未清除**：`performTrashUnmanagedBakFiles()` 删除文件后未清空 `selectedBakFiles` 集合，导致按钮计数与实际列表不同步（`AppPreferencesModel.swift`）
- **完备性测验显示 50%**：`verifyCompleteness()` 的 `expectedFiles` 使用静态文件列表，即使源文件不存在也计入期望集合；修复为仅检查实际存在的源文件（`BackupService.swift`）
- **备份管理状态"未提供"**：`backupOverviewSection` 和 `completenessSection` 当数据为 `nil` 时不显示任何内容；新增引导卡片提示用户执行备份操作（`BackupSectionView.swift`）
- **扫描优化按钮无响应**：`OptimizeScanner.scan()` 从未从 UI 调用；`DeveloperSectionView` 新增扫描按钮，点击触发扫描并展示 findings 列表（`DeveloperSectionView.swift`）
- **多货币 tokens/$ 标签不切换**：`millionRate()` 硬编码 `M/$`；新增 `displayCurrency` 参数，CNY 时显示 `M/¥` 并按汇率换算值（`Components.swift`、`DetailView.swift`）
- **MiMo Credits 额度过时**：月付 Credits 从 60M-1600M 更新为 4.1B-82B，年付从 720M-19200M 更新为 49.2B-984B（`BillingPlanCatalog.swift`、`Pricing.md`）
- **MiMo Credit 消耗规则过时**：从简单倍率更新为具体数值（mimo-v2.5: 2/100/200, mimo-v2.5-pro: 2.5/300/600），新增夜间 0.8x 折扣说明（`Pricing.md`）
- **OpenCodeSkillManifest.swift 截断**：文件被截断仅 75 行，缺失类型定义和 `parseFrontmatter` 函数；补全完整实现（`OpenCodeSkillManifest.swift`）

### Changed

- **设置页侧边栏排序优化**：数据源组（OpenCode/Codex/Skills）上移至全局偏好之后，计费/余额组下移，安全/开发者模式下沉至末尾（`SettingsView.swift`）
- **Skills 页面 Liquid Glass UI 升级**：`TokenCostPalette` 实现 `Equatable` 支持主题切换时视图刷新；HSplitView 背景增加阴影层；侧边栏使用 `settingsInsetSurface()` 替换裸 Material（`ThemePalette.swift`、`OpenCodeSkillsPageView.swift`）
- **开发者模式子功能常驻化**：任务分类、存储优化、多货币、模型对比从 `DeveloperModePreferences` 迁移至 `AppPreferences` 顶层字段，默认开启（`DeveloperModePreferences.swift`、`AppPreferences.swift`）

## [v0.8.5] - 2026-06-07

### Added

- **开发者模式 v1**：新增开发者模式系统，包含 1 个主开关 + 6 个子功能开关（任务分类、存储优化、本地治理、多货币、模型对比、AI 分析）；所有开关通过 `AppPreferences` JSON 持久化，默认关闭（`DeveloperModePreferences.swift`、`AppPreferences.swift`、`AppPreferencesModel.swift`）
- **任务分类引擎**：6 条启发式规则（推理占比高 >20%、缓存重型 >30%、输出为主 >2x、高频短对话 >20 条、高成本 >$5、未分类），对 `DashboardPayload.RawRow` 进行分类，结果在 OpenCode 详情页模型对比区域展示（`TaskClassification.swift`、`DetailView.swift`）
- **存储优化扫描器**：5 种只读元数据扫描 — 过期快照（>30 天）、过多备份（>20 文件或 >10MB）、大 Session 目录（>500MB）、配置碎片化（.bak 文件 >5）、过期最新快照（>7 天）；结果在设置页开发者模式 Tab 的治理面板中展示（`OptimizeScanner.swift`、`SettingsView.swift`）
- **本地治理面板**：显示 OpenCode 配置目录、Skills 目录、Session 目录的文件数量和访问状态，基于 `DeveloperFileAccessPolicy` 允许列表/禁止列表门控（`DeveloperFileAccessPolicy.swift`、`SettingsView.swift`）
- **集中化货币转换服务**：抽取 `TokenCostCurrencyService` 替代散落的 `$ → ¥` 转换逻辑，所有价格展示统一经过此服务（`TokenCostCurrencyService.swift`、`DashboardAnalytics.swift`）
- **开发者模式说明文档弹窗**：参考 `PricingDocView` 模式，新增 `DeveloperModeDocView` 弹窗，包含概览（四大原则）、功能说明（6 个子功能）、使用方法（3 步指引）、安全边界（4 条保证）；设置页开发者模式 Tab 右上角 `doc.text` 图标按钮触发（`DeveloperModeDocView.swift`、`SettingsView.swift`）
- **模型对比免责声明**：当 `modelCompareEnabled` 开启时，OpenCode 详情页模型对比区域底部显示成本分摊估算说明（`DetailView.swift`）
- **开发者模式测试覆盖**：新增 4 个测试文件覆盖 `DeveloperModePreferences`、`DeveloperFileAccessPolicy`、`OptimizeScanner`、`TaskClassification`（`Tests/CodexTokenCostCoreTests/`）
- **开发者模式文档**：新增治理规范、灰度功能执行方案、发布模型与边界记录 3 份文档（`docs/`）
- **开发者模式安全脚本**：新增 banned symbols 检查脚本和 allowlist 配置（`script/check_developer_mode_banned_symbols.sh`）

### Security

- **开发者模式四原则**：所有开发者模式功能严格遵循「本地、只读、确定性、可解释」原则；`DeveloperFileAccessPolicy` 实现允许列表/禁止列表门控，禁止访问凭证文件（`~/.codex/auth.json`、`~/.ssh/` 等）；不新增网络调用，不修改源数据（`DeveloperFileAccessPolicy.swift`、`SECURITY.md`）

## [v0.8.2] - 2026-06-05

### Fixed

- **DeepSeek reasoning tokens 未计入成本**：`apiCost()` 新增 `reasoning` 参数，reasoning tokens 按 output 费率计费；修复 DeepSeek V4 Pro thinking mode 下 `syntheticApiCost` 被严重低估的问题，导致 Provider 性价比排行虚高（`DashboardAnalytics.swift`）
- **模型对比排行成本分配偏差**：`buildModelComparisonRows()` 从 Provider 总成本按 token 比例分配改为各模型独立计算 `apiCost()`，消除同一 Provider 内不同单价的模型（V4 Flash vs V4 Pro）之间的成本均摊偏差（`DashboardAnalytics.swift`）
- **Provider 成本优先使用 app 定价目录**：`providerEffectiveCosts()`、`combinedMonthlyCost()`、`openCodeOverviewCost()` 三处统一将 `syntheticApiCost` 优先级提到 `rawCost` 之前，避免 OpenCode 写入的过时 `$.cost` 污染排名和总览月费（`DashboardAnalytics.swift`、`BillingPlanCatalog.swift`）

## [v0.8.1] - 2026-06-05

### Added

- **多 Provider 余额监控**：余额监控扩展为 OpenCode Go / Codex / OpenCode Zen / DeepSeek 四个 Provider；新增结构化 `BalanceConfiguration`、多币种 `valueEntries` 和配额窗口模型，支持在主页面与菜单栏展示多窗口配额和余额条目（`BalanceModels.swift`、`BalanceManager.swift`、`BalanceOverviewCard.swift`、`MenuBarView.swift`、`DeepSeekBalanceProvider.swift`）
- **关闭窗口后自动隐藏 Dock 图标**：主窗口关闭时自动切换为 `.accessory` 激活策略从 Dock/App Switcher 隐藏，保留 MenuBar 后台运行；通过 MenuBar 重新打开窗口或设置页时自动恢复 Dock 图标（`WindowLifecycleManager.swift`、`AppDelegate.swift`、`MenuBarView.swift`、`TokenCostApp.swift`）
- **App 层单元测试 target**：新增 `CodexTokenCostAppTests`，覆盖窗口策略切换、窗口识别、观察者管理，以及 `AppPreferencesModel` 的余额配置持久化（`Package.swift`、`Tests/CodexTokenCostAppTests/`）

### Changed

- **设置页模块化重构**：设置页按 `全局偏好 / 计费方案 / 余额监控 / OpenCode / Codex / Skills 面板 / 安全边界` 七个模块重排，一级模块可折叠，OpenCode / Codex 长列表保留二级折叠与分页（`SettingsView.swift`、`Components.swift`、`Localizable.strings`）
- **设置页横向响应式布局**：模块内短控件统一切换为响应式控制网格、动作条和字段区；默认 900 宽窗口下优先两列排布，显著减少 `余额监控`、`Skills 面板`、`OpenCode / Codex 来源` 的空白浪费（`SettingsView.swift`、`Components.swift`）
- **余额监控配置统一写入入口**：`balanceConfig` 正式进入 `AppPreferences`，所有 Provider 开关和 `allowEnvironmentCredentials` 改为统一通过 `AppPreferencesModel.updateBalanceConfiguration()` 持久化（`AppPreferences.swift`、`AppPreferencesModel.swift`、`TokenCostApp.swift`）

### Fixed

- **OpenCode Go 环境变量开关真正生效**：`allowEnvironmentCredentials` 不再只是 UI 开关，运行时凭证发现、测试连接和 checker 构建都会按当前设置决定是否读取环境变量（`SecureCredentialStore.swift`、`OpenCodeGoBalanceProvider.swift`、`BalanceManager.swift`、`SettingsView.swift`）
- **Provider 凭证发现边界收紧**：OpenCode Go 与 DeepSeek 改为只读取各自显式配置的凭证，不再跨 Provider 回退错误的 `api_key` / `key` 字段（`AuthTokenProvider.swift`）
- **余额配置启动同步与测试回归**：`BalanceManager` 启动时直接吃已持久化配置，排序与启用列表稳定；补齐 `BalanceManager`、环境变量 gating、Keychain 发现和 AppPreferences round-trip 测试（`BalanceManager.swift`、`CodexTokenCostCoreTests.swift`、`AppPreferencesModelTests.swift`）

### Security

- **OpenCode Go 凭证边界正式固化**：auth cookie 继续只进 macOS Keychain，环境变量 `OPENCODE_GO_WORKSPACE_ID` / `OPENCODE_GO_AUTH_COOKIE` 默认禁用，只有用户在设置中显式开启后才参与发现链路（`SecureCredentialStore.swift`、`SECURITY.md`）
- **OpenCode Zen CLI 校验增强**：二进制定位增加固定路径、签名校验与哈希辅助能力，拒绝继续依赖宽松 PATH 回退（`OpenCodeZenBalanceProvider.swift`）

## [v0.8.0] - 2026-06-04

### Added

- **总计页每日用量热力图**：新增 OpenCode + Codex 合计热力图，以过去 52 周为窗口展示每日 token 用量；热力图数据由 `TokenHeatmapBuilder` 合并双源日聚合、自动排除未来日期，并提供按日期升序的 `allCells` 供 UI 自适应排列（`TotalView.swift`、`TokenHeatmapGrid.swift`、`TokenHeatmapBuilder.swift`）
- **共享趋势图组件**：新增 `TokenTrendChartView` 与 `TokenTrendRangePicker`，Codex 页面和 OpenCode 页面共用同一套曲线、渐变面积、hover tooltip 和 7/30 日范围切换（`TrendChartView.swift`、`CodexPageView.swift`、`DetailView.swift`）
- **图表与计价回归测试**：新增热力图双源合并、日期排序、未来日期过滤和 7x52 兼容布局测试；补充 DeepSeek V4 官方 API 定价回归测试，防止计价口径误改（`CodexTokenCostCoreTests.swift`）

### Changed

- **OpenCode 趋势图 UI 与 Codex 对齐**：OpenCode 趋势图改为与 Codex 页面一致的单曲线实际 token 趋势；缓存读/写保留在 hover tooltip 中，不再额外绘制第二条缓存曲线，避免两个页面视觉口径不一致（`DetailView.swift`）
- **Codex 趋势图增加 7/30 日切换**：Codex 趋势图保留原有视觉风格，并补齐与 OpenCode 一致的时间范围控件（`CodexPageView.swift`）
- **热力图卡片内自适应填充**：热力图卡片高度保持不变，内部 cells 根据卡片可用宽高自动计算列数和 cell size，按日期顺序自动换行排列，避免固定 52 列导致过小或排列异常（`TokenHeatmapGrid.swift`）

### Fixed

- **趋势图悬浮状态重置**：共享趋势图在数据点集合变化时自动清空 hover 选中状态，避免切换 7/30 日或刷新数据后 tooltip 停留在旧点位（`TrendChartView.swift`）
- **热力图日期顺序问题**：热力图 UI 不再依赖 7x52 固定矩阵的视觉顺序，统一使用按日期升序的 cells 渲染，确保自动换行后仍保持正确时间顺序（`TokenHeatmapBuilder.swift`、`TokenHeatmapGrid.swift`）

### Security

- v0.8.0 仅新增本地派生图表和测试覆盖，不新增数据写入面或网络请求；OpenCode / Codex 源数据仍保持只读访问。

---

## [v0.7.0] - 2026-06-02

### Added

- **OpenCode Skills 只读面板**：发现 global skill 目录，解析 SKILL.md frontmatter，可视化 permission 规则链与 8-agent 可用性矩阵；多维度过滤（来源/状态/标签），Section 分组列表，Liquid Glass 毛玻璃 UI，Skill 正文预览（折叠/展开），Settings 页 Skills 显示偏好（`OpenCodeSkillsPageView.swift`、`OpenCodeSkillManifest.swift`、`OpenCodeSkillDiscovery.swift`、`OpenCodeSkillPermissions.swift`、`OpenCodeSkillsReadOnlyStore.swift`、`OpenCodeSkillsModel.swift`、`AppPreferences.swift`）

### Fixed

- **设置页订阅方案 Picker 不再显示 API 按量计费选项**：过滤 `usageBased` 类型 preset（如 DeepSeek API 按量计费、Business Codex paygo），仅保留固定月费型订阅方案；旧配置中 `usageBased + subscribed=true` 会在解析和 UI binding 层回正到默认固定订阅，关闭订阅开关后才走 API 计费路径（`BillingPlanCatalog.swift`、`AppPreferencesModel.swift`、`SettingsView.swift`）
- **总计页 OpenCode 卡片总成本口径修复**：OpenCode 合计与 OpenCode 卡片总成本统一改为 `combinedMonthlyCost - Codex 订阅费用`，不再优先使用 `openCodeOverviewCost` 或兜底 `summary.totalCost`，消除关闭 DeepSeek 订阅后 195.96 / 1090.05 两条计算路径来回跳的问题（`BillingPlanCatalog.swift`、`TotalView.swift`、`Localizable.strings`）

### Changed

### Security

- v0.7.0 Skills 面板为**纯只读**，无安全姿态变更

---

## [v0.6.0] - 2026-05-26

### Added

- **设置持久化加固**：全局 Theme 从 `TokenCostSettings` 迁移至 `AppPreferences`（统一全局偏好，修复多存储文件 theme 不一致问题）；新增 `scenePhase` 终止保存钩子确保设置落盘；内存缓存 + 写穿透模式优化（`AppPreferences.swift`、`AppPreferencesModel.swift`、`Models.swift`、`TokenCostApp.swift`、`ContentView.swift`）
- **设置保存稳定性**：`AppPreferencesStore` 和 `SettingsStore` 保留 `.atomic` 原子写入与写前备份，移除会误判失败并阻塞主线程的写后同步回读校验（`AppPreferences.swift`、`SettingsStore.swift`）
- **备份轮转上限**：设置备份保留最近 10 份，防止无限累积（`AppPreferences.swift`、`SettingsStore.swift`）
- **DeepSeek API 按量费用计入总览**：`DashboardAnalytics` 中 `apiCost` 计算扩展至全 Provider；`providerEffectiveCosts` 在 rawCost 为 0 时兜底 `syntheticApiCost`；新增 `deepseek-chat`/`deepseek-reasoner` model alias 映射到 `deepseek-v4-flash`/`deepseek-v4-pro`；`TotalView.openCodeOverviewCost` API 模式使用 analytics + summary 双重 fallback（`DashboardAnalytics.swift`、`TotalView.swift`）
- **人民币/美元计价切换**：新增 `DisplayCurrency` 枚举和 `AppPreferences.displayCurrency` 字段；设置页新增币种切换 Picker；总计页、OpenCode 详情页所有价格展示均随币种动态切换；自定义月费输入根据币种自动换算（`AppPreferences.swift`、`BillingPlanCatalog.swift`、`Components.swift`、`AppPreferencesModel.swift`、`SettingsView.swift`、`TotalView.swift`、`DetailView.swift`）
- **内置定价文档**：`Pricing.md` 新增 DeepSeek API 价目表（中英双语）
- **菜单栏总计页信息**：菜单栏新增总计概述卡片（综合月费 / 综合 Input Tokens / OpenCode 消息数 / Codex 会话数）和最近 7 天 OpenCode 日用量迷你趋势图；OpenCode 的 API 模式费用通过 `TokenCostDashboardAnalytics` 计算、订阅模式下直接读取 `monthlyUSD`；综合费用计入全部五个 Provider 的已订阅方案；趋势图数据直接在 `rawData` 上按日期分组求和，不走完整 Analytics 管线（`MenuBarView.swift`、`Localizable.strings`）
- **Keychain 静默读取**：`SecureCredentialStore.read()` 使用 `kSecUseAuthenticationUI = kSecUseAuthenticationUISkip`，无授权时静默返回 nil 不弹窗；`discoverCredentials()` 添加内存缓存避免重复读取；首次凭证写入时"Always Allow"一次性授权长期生效（`SecureCredentialStore.swift`）
- **Keychain 设备锁定**：`kSecAttrAccessible` 改为 `WhenUnlockedThisDeviceOnly`，凭证不跨设备 iCloud 同步（`SecureCredentialStore.swift`）
- **OpenCode Zen CLI 路径修复**：`locateBinary()` 覆盖 5 个标准安装路径（Homebrew + 官方 install script），每个路径带 `codesign` 签名校验（`OpenCodeZenBalanceProvider.swift`）
- **设置 JSON 兼容解码**：修正 `ID` / `USD` 缩写字段与 `convertFromSnakeCase` 的映射，确保 `preset_id`、`custom_monthly_usd`、`selected_source_id`、`opencode_go_workspace_id` 能稳定往返解码（`AppPreferences.swift`、`BillingPlanCatalog.swift`、`Models.swift`）
- **启动 Keychain 写入移除**：`AppPreferencesModel.init()` 不再每次启动写入 `workspaceID` 到 Keychain（`AppPreferencesModel.swift`）
- **DeepSeek 月费参考预设**：新增 `deepseek-api-cn-monthly` 预设方案（¥50/月估），方便用户将 DeepSeek 费用纳入总计页（`BillingPlanCatalog.swift`）
- **统一计费计算模型**：重构 `billingOverridesByProviderKey()` 覆盖全部 5 个 Provider（不再仅限 OpenCode），每个 Provider 独立判断：已启用固定订阅用月费，否则走 API 估算；新增 `openCodeOverviewCost()` 和 `combinedMonthlyCost()` 统一入口，`TotalView` 和 `MenuBarView` 改为共用同一公式，消除双重计数和 fallback 不一致；降级 `DashboardAnalytics` 中硬编码订阅表为 `legacyFallbackMonthlyCosts`，用户方案优先；总成本 UI 文案明确为「已启用订阅费用 + 未订阅部分 API 估算成本」；全部订阅关闭时总成本全部按 API 估算（`BillingPlanCatalog.swift`、`DashboardAnalytics.swift`、`TotalView.swift`、`MenuBarView.swift`、`Localizable.strings` 中英双语、`Pricing.md`）
- **写后验证诊断日志**：`SafeFileStore`、`AppPreferencesStore`、`SettingsStore` 在 DEBUG 模式下输出 encode/decode 往返的 JSON 内容及验证失败信息（`SafeFileStore.swift`、`AppPreferences.swift`、`SettingsStore.swift`）

### Fixed

- **App 设置重启后回到默认值**：移除保存后立即回读 + `Thread.sleep` retry 的误判路径，并修复 snake_case JSON 解码中 `ID` / `USD` 缩写字段不匹配导致的 fallback-to-defaults（`AppPreferences.swift`、`SettingsStore.swift`、`BillingPlanCatalog.swift`、`Models.swift`）
- **Keychain 自动发现边界过宽**：余额自动刷新只静默读取已保存 Keychain、环境变量和 opencode-bar 配置，不再自动触发浏览器 Cookie 提取或把 env/config 写回 Keychain；浏览器导入仅保留在用户确认的 Settings 操作中（`SecureCredentialStore.swift`、`SettingsView.swift`）
- **总计页总成本被 OpenCode 阻塞**：`TotalView.combinedCost` 和 `MenuBarView.combinedCost` 此前以 `guard let openCodeOverviewCost else { return nil }` 阻塞，导致 OpenCode 未配置/无数据时总成本直接显示「不提供」，忽略已订阅的其他 Provider。现已改为各 Provider 独立累加，任一有费用即显示（`TotalView.swift`、`MenuBarView.swift`）
- **CodexSessionModel 启动时非必要自动 persist**：移除 `bootstrap()` 中 load 成功后无条件 `persistSettings()` 调用，避免写后验证失败干扰正常的设置加载错误提示（`CodexSessionModel.swift`）
- **persist 错误不再覆盖设置加载警告**：`TokenCostModel.persistSettings()` 和 `CodexSessionModel.persistSettings()` 在 save 失败时不再将 `settingsLoadWarningMessage` 覆盖为 save 错误信息，改为仅在 DEBUG 模式输出日志（`TokenCostModel.swift`、`CodexSessionModel.swift`）
- **DeepSeek V4-Pro 定价更新**：促销价（2.5折）已于 2026/05/31 到期，正价已生效：input $1.74、output $3.48、cacheRead $0.0145（`DashboardAnalytics.swift`、`docs/Provider 计费定价速查.md`）
- **总计页总成本双重计数已彻底解决**：通过统一 `combinedMonthlyCost()` 消除 TotalView 和 MenuBarView 的重复手动累加公式，全部 5 个 Provider 的费用由同一入口计算（`BillingPlanCatalog.swift`、`TotalView.swift`、`MenuBarView.swift`）
- **取消订阅后费用反涨已彻底解决**：`providerEffectiveCosts()` 现在对全部 Provider 生效，billingOverride 覆盖后不再错误回退到 rawCost，用户方案贯穿 analytics 全链路（`DashboardAnalytics.swift`、`BillingPlanCatalog.swift`）
- **OpenCode 硬编码 fallback 移除**：`providerEffectiveCosts()` 中针对 `"opencode-go"` 的特殊 case 和 `subscriptionMonthlyCosts["opencode-go"]` 硬编码 $10 已删除，改为与其他 Provider 一致的逻辑（`DashboardAnalytics.swift`）
- **OpenCode 卡片计价模式区分**：`TotalView` OpenCode 卡片在订阅模式下显示方案价格而非 analytics API 费用（`TotalView.swift`）
- **billingOverride 范围修正**：`billingOverridesByProviderKey()` 从遍历全部 5 个 Provider 改为仅输出 OpenCode override，避免 `analytics` 计算 OpenCode 数据源费用时被其他 Provider 的月费覆盖（`BillingPlanCatalog.swift`）

### Changed
- **总计页移除冗余设置卡片**：`TotalView` 删除 `overviewSettingsCard` 和 `openCodePlanSubtitle`，OpenCode 计价模式切换统一在设置页管理（`TotalView.swift`）

### Security

- **Release 构建日志清理**：`UpdateChecker.swift` 和 `UpdateCheckerModel.swift` 中 8 处 `print()` 增加 `#if DEBUG` 包裹，防止路径/文件大小泄露
- **浏览器临时文件隔离**：Cookie/History SQLite 副本从 `/tmp` 迁移至沙箱专用子目录（`BrowserCookieExtractor.swift`）
- **Keychain 删除校验**：`SecItemDelete` 返回值检查，失败时 DEBUG 日志告警（`SecureCredentialStore.swift`）
- **路径穿越加固**：`SafeFileStore.relativeURL` 增加 `..` 路径组件早期拒绝（`SafeFileStore.swift`）
- **opencode CLI 路径锁定**：禁用 `which` 从 PATH 查找，仅用已知固定路径（`OpenCodeZenBalanceProvider.swift`）
- **更新包签名校验**：ditto 解压后 `codesign --verify` 验证 .app 签名完整性（`UpdateChecker.swift`）
- **扫描根白名单**：禁止添加 `/`、`/System`、`/Users` 等系统根路径为扫描根（`SourceDiscoveryService.swift`）
- **运行时根标识符统一**：`TokenCostPaths.bundleIdentifier` 与 `CodexAppPaths` 统一为 `com.yanghaoran.CodexTokenCost`（`AppPaths.swift`）
- **Keychain 静默授权**：`SecItemCopyMatching` 使用 `kSecUseAuthenticationUI = kSecUseAuthenticationUISkip`，已有授权静默返回，无授权不弹窗；自动刷新链路不写入 Keychain、不读取浏览器 Cookie（`SecureCredentialStore.swift`）
- **opencode CLI 路径校验**：多路径候选 + `codesign --verify` 签名校验，防止执行未签名二进制（`OpenCodeZenBalanceProvider.swift`）

## [v0.5.1] - 2026-05-20

> 相对 `v0.5.0` 的累计变更。

### Added
- **浏览器凭证自动导入**：从 Edge / Chrome / Brave / Arc 自动提取 opencode.ai 的 Cookie 和 Workspace ID，通过 Keychain + PBKDF2 + AES-128-CBC 本地解密后存入钥匙串（`BrowserCookieExtractor.swift`、`CommonCryptoBridge.c`、`SecureCredentialStore.swift`、`SettingsView.swift`）
- **OpenCode Go 设置页测试连接按钮**：独立校验凭证配置，不触发全量刷新和 backoff（`SettingsView.swift`、`BalanceManager.swift`）

### Changed
- **菜单栏刷新按钮合并**：将菜单栏中三个独立按钮合并为一个「刷新全部」按钮，快捷键简化为单一 `Cmd+R`（`MenuBarView.swift`、`TokenCostCommands.swift`）
- **菜单栏余额区域增加刷新按钮**：在余额摘要底部增加「刷新余额」按钮（`MenuBarView.swift`）
- **模型分布与 Provider 分布饼图卡片等高**：替换为 `HStack` + `PreferenceKey` 方案（`DetailView.swift`）
- **版本更新检查交互重构**：保留启动自动静默检查（24h 缓存），新增工具栏「检查更新」手动按钮（即时调 API 忽略缓存）；有更新时显示「更新」/「稍后」双按钮替代原直接下载；无更新时显示「已是最新版本 vX.Y.Z」3 秒自动消失；新增 `manualCheck()`、`dismissUpdate()` 方法，`checkForUpdate()` 改为静默模式（`UpdateCheckerModel.swift`、`ContentView.swift`、`Localizable.strings`）

### Fixed
- **OpenCode Zen 费用 Go 模型成本扣减不完全**：增强模型名称匹配（`OpenCodeGoBalanceProvider.swift`）
- **OpenCode Go 凭证链路修复**：`workspaceID` 保存时同步写入 Keychain（`AppPreferencesModel.swift`、`SecureCredentialStore.swift`）
- **OpenCode Go 仪表盘 HTML 解析修复**：从 Next.js 格式迁移到 SolidJS SSR hydration，三轮窗口各两组正则并改为容错模式（`OpenCodeGoDashboardFetcher.swift`）
- **Dashboard 解析失败分层错误提示**：区分「格式变更」vs「cookie/workspace 不匹配或未订阅」，并增加 DEBUG HTML dump（`OpenCodeGoDashboardFetcher.swift`）
- **浏览器导入交叉合并修复**：当浏览器只找到 cookie 而 workspaceID 已在 Keychain（或反之）时，不再丢弃部分凭据，改为自动拼合完整凭证（`SecureCredentialStore.swift`、`SettingsView.swift`）

## [v0.5.0] - 2026-05-19

### Fixed
- **总计页总成本未计入 MiniMax / Xiaomi MiMo 订阅费用**：`TotalView.combinedCost` 此前只计算 OpenCode + Codex 两个 provider，现已纳入全部四个 provider 的已订阅方案费用 (`TotalView.swift`)
- **总计页 OpenCode 计价卡片 subtitle 在 API 模式下误显订阅价格**：`overviewSettingsCard` 的 OpenCode 小卡片 subtitle 此前始终显示 `resolvedOpenCodePlan.priceDescription`（如 $10/月），现根据 `openCodePricingMode` 动态切换：API 模式显示「按量计费」，订阅模式显示方案价格
- **Codex 总览卡片的 subtitle 依赖 Codex 数据源存在**：`codexOverviewCost` 此前 guard `codexSummary != nil`，导致无 Codex 数据时 `combinedCost` 整体为 nil。现已移除该依赖，Codex 订阅费用独立于数据源
- **定价文档弹窗表格分隔符被错误渲染为数据行**：`PricingDocView.buildTable()` 未过滤 markdown 表格的 `|---|---|` 分隔符行，导致分隔符行作为数据行渲染。现已增加过滤逻辑，跳过仅由 `-`/`:`/空格组成的行（`PricingDocView.swift`）
- **总计页指标卡片布局未对齐/溢出**：三个卡片区（总计/OpenCode/Codex）的 `LazyVGrid` 使用 `.adaptive(minimum:)` 导致宽窗口时超过 4 列，且副标题较长的卡片高度不一致。现已改为固定 4 列 `GridItem(.flexible())` + 每个 `TokenMetricCard` 统一 `maxHeight: .infinity` 对齐（`TotalView.swift`）
- **OpenCode 详情页来源修改时间显示 UTC 而非本地时间**：`SourceDiscoveryService.modificationDate(for:)` 使用 `ISO8601DateFormatter().string(from:)` 输出 UTC 时间字符串，UI 层直接显示未做本地时区转换。现新增 `TokenCostFormatters.localDateTime(_:)` 方法，解析 ISO 8601 字符串后以 `DateFormatter`（不设 `timeZone`，自动跟随系统时区）格式化为本地时间显示（`Components.swift`、`DetailView.swift`）
- **OpenCode 详情页第一行来源卡片高度不对齐**：`sourceHeader` 中 `LazyVGrid` 使用 `.adaptive(minimum: 220)` 导致来源路径卡片因长文本换行而高于同行其他卡片。现改为固定 3 列 `GridItem(.flexible())` 等宽 + 每张卡片 `.frame(maxHeight: .infinity, alignment: .topLeading)` 统一行高（`DetailView.swift`）

### Added
- **未订阅选项**：设置页四个 Provider 计费卡片新增「订阅该方案」Toggle 开关。关闭后该 Provider 不会计入总成本（`monthlyUSD = nil`），灵活应对实际未订阅的场景
- **`BillingPlanSelection.isSubscribed` 字段**：向前兼容旧 JSON（缺少 key 时默认 true，保持旧用户行为不变）
- **全局工具栏刷新按钮**：从原有 OpenCode 页 toolbar 重新扫描按钮扩展为全局刷新。总计页→「刷新全部」（同时重扫 OpenCode + 刷新 Codex），OpenCode 页→「重新扫描」，Codex 页→「刷新 Codex」；`SidebarView` 原有本地 toolbar 已移除（`ContentView.swift`、`SidebarView.swift`）
- **刷新进度条**：当 OpenCode 或 Codex 处于扫描/刷新状态时，TabView 上方显示线性进度指示器，参考 Apple HIG 定位在内容区顶部（`ContentView.swift`）
- 新增本地化 key：`tab.action.refreshAll`（中英双语）、`overview.plan.apiCost`、`overview.summary.totalCostAllSubscribedSubtitle`、`settings.billing.subscribed`、`settings.billing.notSubscribed`、`settings.billing.notSubscribedDescription`（中英双语）
- **余额实时监控**：新增 `BalanceManager` 协调器和三个 Provider 余额查询器（OpenCode Go / Codex / OpenCode Zen）。从本地 `auth.json` 安全读取 API key，通过 HTTPS 调用各 Provider 官方 API 获取实时余额/credit/用量百分比。余额快照仅驻留内存，不持久化到磁盘。仪表盘、各详情页、菜单栏均展示余额梯度色条和百分比。设置页可开关余额监控并调整刷新间隔（默认关闭，保持纯本地承诺）
- **余额可视化卡片**：`BalanceOverviewCard` 可折叠组件，按梯度色条（灰/绿/黄/橙/红）展示使用百分比；不可用 Provider 单独显示状态和原因
- **菜单栏余额摘要**：余额开启后在菜单栏显示各 Provider 使用百分比和梯度标签，一目了然
- **版本更新检查**：启动时每天一次自动检查 GitHub Release 最新版本；工具栏以胶囊标签显示「更新」，点击自动下载并以标签背景左→右渐进填充可视化进度；下载后校验文件完整性，点击「安装」打开新版本 .app。涉及文件：`UpdateChecker.swift`、`UpdateCheckerModel.swift`、`ContentView.swift`、`TokenCostApp.swift`、本地化 `Localizable.strings`（中英双语）

### Changed
- `BillingPlanSelection` 从编译器合成 `Codable` 改为手动实现，以支持 `isSubscribed` 字段的向前兼容解码
- `ResolvedBillingPlan` 新增 `isSubscribed: Bool` 字段
- **定价文档弹窗重写**：`PricingDocView` 从单次 `AttributedString(markdown:)` 渲染改为分段解析，自定义标题、引用块、表格布局。表格使用原生 `HStack`+`Divider` 渲染，解决 markdown 表格文字堆叠问题。弹窗添加图标、调整最小尺寸（`PricingDocView.swift`）
- `AppPreferences` 新增 `balanceEnabled`、`balanceRefreshMinutes` 和 `opencodeGoWorkspaceID` 字段（向后兼容）
- `AppPreferencesModel` 新增对应双向绑定
- 全局传参链扩展：`TokenCostApp` → `ContentView` → `TotalView` / `OpenCodePageView` / `CodexPageView` / `SettingsView` / `MenuBarView` 均新增 `balanceManager` 参数
- `BalanceManager` 为 `@MainActor class: ObservableObject`，通过 `@Published` 广播状态
- **OpenCode Go 从 API 模式迁移到 Dashboard 配额模式**：通过 `GET /zen/go/v1/models` 验证 API key，通过 `GET /workspace/{id}/go` 解析 HTML 获取 5小时/每周/每月三个额度窗口
- **OpenCode Go 凭证安全存储**：`SecureCredentialStore` 使用 macOS Keychain (`Security.framework`) 加密存储 authCookie；workspaceID 明文保存于 `AppPreferences`；支持环境变量和 opencode-bar 配置文件自动导入
- **OpenCode Zen 费用去重**：总费用减去 Go 模型成本
- **菜单栏余额条形图**：用紧凑进度条替代纯文字显示
- `BalanceSnapshot` 新增 `tertiaryWindow*` 三字段支持 Go 每月窗口
- SECURITY.md 新增 Keychain 安全声明
- **Release 目录重组**：`dist/` → `release/`，对齐 news-bar 项目结构。新增 `release/latest/`（始终指向最新构建）、`release/versions.json`（结构化版本元数据）、`release/release-notes/`（集中管理）。RELEASE_NOTES 从项目根迁入 `release/release-notes/`。更新 `.gitignore` 规则、CI/CD 脚本路径、开发手册和 README

## [v0.1.1] - 2026-05-18

### Added
- `.github/workflows/ci.yml` — push/PR 时自动 `swift build` 验证编译
- `.github/workflows/release.yml` — tag 推送时自动构建 `.app` 并创建 GitHub Release
- `.github/copilot-instructions.md` — AI agent 项目速查指令
- `.github/CODEOWNERS` — 代码评审归属
- `.gitignore` — 忽略构建缓存和系统文件
- `LICENSE` — MIT License
- `SECURITY.md` — 安全漏洞上报指引
- `docs/架构逻辑链图.md` — 系统架构 Mermaid 图
- `docs/开发手册.md` — 开发指南和发布流程
- `Resources/zh-Hans.lproj/Localizable.strings` / `Resources/en.lproj/Localizable.strings` — app 级中英双语文案
- `Sources/CodexTokenCostCore/AppPreferences.swift` / `Sources/CodexTokenCostApp/Stores/AppPreferencesModel.swift` — 语言与总览计价偏好
- `Sources/CodexTokenCostCore/BillingPlanCatalog.swift` — Provider 订阅 / Token Plan 档位目录，覆盖 OpenCode Go / Zen、ChatGPT Plus / Pro / Business Codex、MiniMax Token Plan、Xiaomi MiMo Token Plan，并支持自定义 USD 月费
- `Sources/CodexTokenCostApp/Views/PricingDocView.swift` / `Sources/CodexTokenCostApp/Resources/Pricing.md` — App 内置只读计费参考文档查看器
- `Tests/` 目录 — 预留测试目录

### Changed
- **项目目录重组**: `Package.swift`、`Sources/`、`Resources/` 从 `app/` 移至项目根，符合 SPM 标准
- `dist/` 从 `app/` 移至项目根，发布产物与源码分离
- `script/build_and_run_codex.sh` 路径引用更新（`APP_PACKAGE_DIR` → 根目录）
- 构建脚本移除自定义环境变量（`HOME`, `XDG_CACHE_HOME`, `CLANG_MODULE_CACHE_PATH`），使用系统默认
- 发布产物按版本号管理（`dist/releases/v0.1.0/`）
- 总览页新增独立 OpenCode 计价选择，仅影响总览成本对照，不改 OpenCode / Codex 独立页的 token 统计
- 设置页新增「计费方案」管理区：每个 provider 可选择官方预设档位或 DIY 自定义 USD/月费；按量计费与 contact-sales 档位可作为说明项，必要时通过自定义月费纳入总成本
- OpenCode 详情页的 Provider 成本分析支持从 AppPreferences 注入计费覆盖；未配置时继续回退到现有默认费用，保持 v0.1.1 旧口径兼容
- 主窗口、设置页、菜单、状态提示与详情页文案已接入本地化层，支持中文 / 英语切换

### Removed
- 废弃的 `app/` 目录及构建缓存（`.build-codex/`, `.spm-*`, `.module-cache-*` 等）
- 旧的构建脚本冗余配置

### Fixed
- Codex 页面中英文本地化补全：修正仍残留的标题、表头、排序文案与 tooltip
- **修复 actual token 重复扣减缓存 bug**：原公式 `actualTokens = max(input - cacheRead - cacheWrite, 0)` 在 OpenCode SQLite 数据中 `$.tokens.input` 已是非缓存值的情况下造成二次扣减，导致 totalActualTokens 趋近于零、缓存命中率虚高至 99.9%、Provider 性价比排行和 Model 价格对比全部错误。修正为 `actualTokens = input + output + reasoning`，与 OpenCode 源码 `getUsage()` 的 token 存储逻辑一致。受影响文件：`DashboardAnalytics.swift`（2处）、`TokenDatabaseClient.swift`（1处）、`Models.swift`（1处）
- 计费偏好兼容迁移：旧版 `app-preferences.json` 缺少计费选择时自动回退默认档位；若曾保存旧形态自定义费用，会迁移为新的 `BillingPlanSelection`
- **修复 totalActualInputTokens 仍用旧公式遗漏**：`DashboardPayload.totalActualInputTokens`（Models.swift:361）此前仍执行 `max(input - cacheRead - cacheWrite, 0)`，在 OpenCode SQLite 中 `input` 已非缓存的语义下造成 cache 二次扣减，直接影响 TotalView 的 OpenCode 实际输入 token 和总实际输入 token 展示。修正为直接求和 `row.input`。

## [0.1.0] - 2026-05-13

### Added
- OpenCode SQLite 数据库 token 用量可视化
  - 自动扫描系统目录发现数据库
  - 支持手动添加目录和数据库文件
  - JSON extract 聚合查询
- Codex JSONL session 文件聚合统计
  - Session 级 token usage 解析
  - 每日 token 趋势图
  - Session 列表（分页+排序+Tooltip）
- 双源总计面板（TotalView）
- 四种主题色（海湾蓝、森林绿、暮光橙、极光紫）
- 缓存分析卡片和 Provider 性价比排行
- 模型价格对比（API 定价 + 订阅成本）
- 数据分布饼图（模型分布 / Provider 分布）
- 每日模型堆叠图
- 详细数据表（50 条窗口，分页排序）
- 设置面板（OpenCode + Codex 独立配置）
- 快照保存与自动轮转（可配置保留数量）
- Helper 子进程架构（CodexTokenCostHelper）
- 构建/运行/调试脚本 `build_and_run_codex.sh`
- 安全只读设计 + SafeFileStore 沙箱文件读写

[Unreleased]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v1.0.3...HEAD
[v1.0.3]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v1.0.2...v1.0.3
[v1.0.2]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v1.0.1...v1.0.2
[v1.0.1]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v1.0.0...v1.0.1
[v1.0.0]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.9.9...v1.0.0
[v0.9.7]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.9.6...v0.9.7
[v0.9.9]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.9.8...v0.9.9
[v0.9.8]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.9.7...v0.9.8
[v0.9.6]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.9.2...v0.9.6
[v0.9.2]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.9.1...v0.9.2
[v0.9.1]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.9.0...v0.9.1
[v0.9.0]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.8.5...v0.9.0
[v0.8.5]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.8.2...v0.8.5
[v0.8.2]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.8.1...v0.8.2
[v0.8.1]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.8.0...v0.8.1
[v0.8.0]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.7.0...v0.8.0
[v0.7.0]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.6.0...v0.7.0
[v0.6.0]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.5.1...v0.6.0
[v0.5.0]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.1.1...v0.5.0
[v0.1.1]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/blackkcold/Token-Cost-App-OC-Codex/releases/tag/v0.1.0
