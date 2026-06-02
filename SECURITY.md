# 安全策略

## 支持的版本

| 版本   | 支持状态       |
|--------|--------------|
| 0.7.0  | Unreleased (开发中) |
| 0.6.0  | 当前稳定版，接受安全报告和修复 |
| 0.5.1  | 当前稳定版，接受安全报告和修复 |
| 0.5.0  | 当前稳定版 |
| 0.1.1  | 当前稳定版，接受安全报告和修复 |
| 0.1.0  | 当前稳定版，接受安全报告和修复 |
| 更早版本 | 不再保证支持   |

## 报告安全漏洞

如发现安全漏洞，请通过以下方式报告：

1. **不要**在公开 Issue 中报告安全漏洞。
2. 发送邮件到项目维护者，或使用 GitHub [Private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) 功能。
3. 请提供详细描述，包括复现步骤、影响范围和可能的修复建议。

我们会在 48 小时内确认收到报告，并在 1 周内给出初步评估结果。

## 安全设计原则

- 本应用**只读**访问 OpenCode 数据库和 Codex session 文件
- 不修改任何源数据文件
- 配置和快照仅写入本地 `Application Support` 目录
- 语言设置、总览计价偏好和 Provider 计费方案选择只写入本地 `config/app-preferences.json`，不接触源数据
- 总览页的实际 token 只是从已有来源数据派生的展示值（按 `input + output + reasoning` 计算），不会回写数据库、session 文件或网络
- 本地化资源只读加载，不会向网络或外部服务传输文案
- 内置计费文档只从 app bundle 资源读取，不开放任意本地文件路径，也不联网更新价格
- 不收集、不上传任何使用数据
- 余额监控功能（v0.1.2+）默认关闭 (`balanceEnabled=false`)，维持纯本地承诺。开启后通过 HTTPS 直接调用各 Provider 官方 API 端点（api.opencode.ai、chatgpt.com 等）获取实时余额；API key 从本地 auth.json 临时读取至内存，30 秒后清除，不持久化到磁盘或日志；所有网络请求使用 ephemeral URLSession，不经过第三方服务器；余额快照仅驻留内存，不写入任何本地文件
- OpenCode Go 配额监控的 authCookie 凭证使用 macOS Keychain (`Security.framework`) 加密存储（`kSecClassGenericPassword` + `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`），不写入明文 JSON 配置文件。workspaceID 为非敏感标识符，仍可在 `AppPreferences` 中保留一份兼容副本，并在用户保存时同步写入 Keychain 供运行时读取
- 浏览器凭证自动导入功能（v0.5.1+）仅读取 Edge / Chrome / Brave / Arc 中 `opencode.ai` 域名的 Cookie 和浏览记录；解密操作通过 Chromium 标准 AES-128-CBC + PBKDF2-SHA1 链路在本地完成，用户需在弹窗中明确确认后才执行；解密的 Cookie 只驻留一次 API 调用的内存生命周期，不写入日志、文件或 UserDefaults；浏览器数据库以 `SQLITE_OPEN_READONLY` + 临时文件副本方式访问，操作完成后自动清理
- 版本更新检查功能（v0.5.0+）仅向 GitHub 公开 API (`api.github.com/repos/blackkcold/Token-Cost-App-OC-Codex/releases/latest`) 发起匿名 GET 请求获取最新 Release 元数据，不携带认证凭据、不收集不上传任何用户数据；下载的 `.zip` 文件经大小与 Content-Length 交叉校验后存放于本地 `Application Support` 沙箱内的 `updates/` 目录，不解压后自动运行；检查频率缓存为每 24 小时一次（启动自动），用户可通过工具栏按钮手动触发即时检查（忽略 24h 缓存），防止 API 限流
- 更新包完整性校验（v0.6.0+）：ditto 解压后的 `.app` bundle 通过 `codesign --verify` 验证签名完整性，防止中间人篡改
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
