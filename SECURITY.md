# 安全策略

## 支持的版本

| 版本   | 支持状态       |
|--------|--------------|
| 1.0.x  | 当前稳定版，接受安全报告和修复 |
| 0.9.x  | 接受安全报告 |
| 更早版本 | 不再保证支持   |

## 报告安全漏洞

如发现安全漏洞，请通过以下方式报告：

1. **不要**在公开 Issue 中报告安全漏洞。
2. 发送邮件到项目维护者，或使用 GitHub [Private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) 功能。
3. 请提供详细描述，包括复现步骤、影响范围和可能的修复建议。

我们会在 48 小时内确认收到报告，并在 1 周内给出初步评估结果。

## 安全设计原则

- 本应用**只读**访问 OpenCode 数据库和 Codex session 文件，不修改任何源数据文件
- **趋势图与热力图（v0.8.0+）**：仅基于已读取的 OpenCode / Codex 本地聚合数据做 UI 派生展示，不新增写入面、不上传图表数据。
- **OpenCode Skills 只读面板（v0.7.0+）**：仅读取 skill 目录和配置进行分析展示，不做任何写入操作。权限可视化基于全局配置文件只读解析，不修改 `permission.skill` 规则。
- 配置和快照仅写入本地 `Application Support` 目录
- 语言设置、总览计价偏好、Provider 计费方案选择和余额监控配置只写入本地 `config/app-preferences.json`，不接触源数据
- 总览页的实际 token 只是从已有来源数据派生的展示值（按 `input + output + reasoning` 计算），不会回写数据库、session 文件或网络
- 本地化资源只读加载，不会向网络或外部服务传输文案
- 内置计费文档只从 app bundle 资源读取，不开放任意本地文件路径，也不联网更新价格
- 不收集、不上传任何使用数据
- 余额监控功能默认关闭 (`balanceEnabled=false`)。开启后通过 HTTPS 直接调用各 Provider 官方端点；API key 从已有本地 auth 文件按需读取，浏览器 Cookie 优先从内存缓存读取；所有网络请求使用 ephemeral URLSession，不经过第三方服务器，余额快照仅驻留内存。
- OpenCode Go 与 Ollama Cookie 写入 App 专用目录中的 AES-256-GCM 加密文件；随机主密钥与密文分别以 `0600` 权限保存，目录权限为 `0700`。该方案避免日常访问 App 自身 Keychain 项目，但无法防御以同一 macOS 用户身份运行且已获得文件读取权限的恶意进程。
- 浏览器凭证自动导入仅读取 Edge / Chrome / Brave / Arc 中目标域名的 Cookie/History 数据库。浏览器 Safe Storage 查询使用“禁止认证 UI”模式，无法静默读取时直接跳过，不触发系统授权弹窗；SQLite 副本只读打开并在操作后清理。
- 凭证自动引导：余额监控启用后先验证 App 的本地加密缓存；缓存有效时不读取浏览器。缓存无效或缺失时，按浏览器/Profile 顺序逐个验证候选 Cookie，认证失败才继续下一项；网络不可用时保留本地缓存。成功候选写入内存与本地加密缓存；全部耗尽时 UI 显示未找到 Cookie，OSLog 只记录来源与失败类别，不记录 Cookie、密钥或完整路径。
- 版本更新检查仅匿名读取 GitHub 公开 Release API。自动安装要求 Release 同时提供 Ed25519 签名 manifest；客户端先验证版本、Bundle ID、架构、文件名、长度和 SHA-256，再以流式方式下载到权限受限 staging 目录，限制最大体积，任何失败都会清理临时产物。
- 更新包完整性校验：签名 manifest 保护 zip 内容，解压后的唯一 `.app` 仍通过 `codesign --verify --deep --strict` 验证；缺少 manifest 的历史 Release 不进入自动安装流程。
- 浏览器临时文件隔离（v0.6.0+）：Cookie/History SQLite 副本从 `/tmp` 迁移至沙箱专用子目录，权限 0700，操作完成后自动清理
- 路径穿越加固（v0.6.0+）：`SafeFileStore.relativeURL` 增加 `..` 路径组件早期拒绝
- Keychain 写入校验（v0.6.0+）：`SecItemDelete` 返回值检查，防止旧凭证残留
- opencode CLI 路径锁定（v0.6.0+）：禁用 PATH 查找，仅用已知固定路径执行
- 扫描根白名单（v0.6.0+）：禁止添加 `/`、`/System`、`/Users` 等系统根路径
- 设置持久化完整性（v0.6.0+）：所有设置通过 `Data.write(.atomic)` 原子写入，并在覆盖前保留最近 10 份备份；不做主线程写后 sleep 回读，避免误判保存失败
- 终止保存守护（v0.6.0+）：`scenePhase` 钩子在 app 退入后台时最终落盘所有设置域
- Release 日志净化（v0.6.0+）：`UpdateChecker` 中所有文件路径/状态输出仅 DEBUG 构建可见
- Keychain 静默读取（v0.6.0+）：`SecItemCopyMatching` 使用 `kSecUseAuthenticationUI = kSecUseAuthenticationUISkip`，已有"Always Allow"授权静默返回，无授权不弹窗；`discoverCredentials()` 添加内存缓存避免同 session 重复 Keychain 访问；自动刷新链路只读凭证，不自动写入 Keychain，不触发浏览器 Cookie 导入
- Keychain 设备锁定（v0.6.0+）：`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，凭证不跨设备 iCloud 同步
- Ollama Cloud 用量监控：Cookie 从内存缓存读取，并可由本地 AES-256-GCM 加密缓存或经过验证的浏览器候选补充；通过 ephemeral URLSession 访问 `ollama.com/settings`，不写入日志、不上传第三方服务。旧版明文 Cookie 文件回退已移除。

## 开发者模式安全边界（v0.9.0+）

### 概述

开发者模式（Developer Mode）是一个可选的高级功能集，默认完全关闭。启用后提供任务分类、存储优化、本地治理等只读分析能力。

### 安全设计

- **默认关闭**：`DeveloperModePreferences.isEnabled` 默认为 `false`，所有子功能同样默认关闭
- **只读优先**：所有 v1 功能仅读取元数据（文件大小、数量、修改时间），不读取文件内容
- **独立目录**：所有 Developer Mode 代码位于 `Sources/CodexTokenCostCore/DeveloperMode/` 和 `Sources/CodexTokenCostApp/DeveloperMode/`
- **CI 禁止符号检查**：`script/check_developer_mode_banned_symbols.sh` 在 CI 中自动扫描 7 类 39 个禁止符号
- **本地执行**：Phase 0-3 不新增任何网络请求，不启动外部进程
- **凭证隔离**：Developer Mode 禁止访问 `SecureCredentialStore`、`auth.json`、Keychain
- **文件访问策略**：`DeveloperFileAccessPolicy` 实现 allowlist/blocklist 路径控制
- **持久化隔离**：Developer Mode 状态写入 `app-preferences.json`，与源数据完全分离

### 文件访问控制

| 路径 | 访问权限 | 说明 |
|------|---------|------|
| `~/Library/Application Support/com.yanghaoran.CodexTokenCost/config/*.json` | 元数据只读 | 文件大小、修改时间 |
| `~/Library/Application Support/com.yanghaoran.CodexTokenCost/snapshots/*/*.json` | 元数据只读 | 每 source 快照数、最老时间 |
| `~/.codex/sessions/**/*.jsonl` | 元数据只读 | 文件数量、总大小、最后修改时间 |
| `~/.codex/auth.json` | **禁止** | 直接凭证文件 |
| `~/.ssh/`, `~/.gnupg/`, `~/Library/Keychains/` | **禁止** | 高敏凭证区 |
| 浏览器目录 | **禁止** | Cookie/History SQLite |
| 云凭证目录 | **禁止** | AWS/Docker/K8s 等 |
