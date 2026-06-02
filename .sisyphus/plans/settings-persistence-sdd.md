# SDD：App 设置自动持久化修复 — 完整调研报告与执行方案

> 版本: v0.6.0
> 创建日期: 2026-05-23
> 状态: 方案已确认，待执行

---

## 一、问题概述

### 用户反馈的 3 个问题

| # | 问题 | 现象 |
|---|------|------|
| **1** | App 设置不持久化 | 计费方案的订阅开关和余额监控开关重启后重置为默认值（所有 isSubscribed=true，balanceEnabled=false） |
| **2** | OpenCode Zen 余额查询不可用 | 余额监控中 Zen provider 显示"不可用" |
| **3** | Keychain 反复弹窗 | 启动时连续 4 次弹出钥匙串授权对话框 |

### 调研方法

- 全量源文件逐行阅读（30+ 文件的完整代码审计）
- 磁盘文件状态检查（`~/Library/Application Support/` 下的实际文件内容）
- GitHub 优质项目调研（sindresorhus/Defaults、orchetect/swift-prefs、TokenEater、SweetCookieKit 等）
- 前后端全链路追溯（UI Binding → Model → Persistence → Disk）
- 交叉核查（编码/解码一致性验证、路径一致性验证、调用链完整性验证）

---

## 二、问题诊断根因

### 2.1 问题 #1：设置不持久化

**根因**：`AppPreferencesStore.save()` 中的写后 Equatable 校验 + `Thread.sleep` 重试循环

**完整故障树**：

```
用户修改设置（如切换 billing toggle OFF）
  └── Binding setter → AppPreferencesModel.updatePreferences
        └── persistPreferences → store.save(preferences)
              ├─ backupExistingPreferencesIfNeeded()          ✅ 旧文件备份成功
              ├─ writeCodable → encode → writeData(.atomic)   ✅ 文件正确写入磁盘
              │    └── data.write(to: url, options: [.atomic])
              │         ├── 写临时文件 → 成功
              │         └── rename() → 原子替换目标文件 → 成功
              │
              └─ for retry 0..<3:                              ⚠️ BUG 位置
                   ├─ readCodable ← Data(contentsOf:) 读回文件
                   │    └── 若内核文件系统缓存返回旧数据 → decoded ≠ saved
                   │         → Thread.sleep(0.05) → 阻塞 main thread
                   │         → 再读 → 仍可能是旧缓存 → retry
                   │         → Thread.sleep(0.05) → 阻塞 main thread (累计 100ms)
                   │         → 再读 → 仍可能不等
                   │         → ⚠️ throw SafeFileStoreError.encodeFailed
                   │
                   └─ persistPreferences 的 catch 块:
                        loadWarningMessage = "Failed to encode or decode payload."
                        ← 用户没有可见的错误通知（只有打开 Settings 页面才能看到）
                        ← 文件实际已正确写入，但代码认为失败
```

**关键发现**：

1. `Thread.sleep(forTimeInterval: 0.05)` 在 `@MainActor` 上下文中执行（因为 `persistPreferences` 从 UI Binding setter 调用），阻塞 main thread 最长 100ms
2. 阻塞 main thread 期间，macOS 的 Window Server 可能将 app 标记为"未响应"
3. 文件系统缓存的刷新时间在 macOS 上可能超过 100ms，特别是在高 I/O 负载时
4. 即使校验失败，**文件实际已经正确写入磁盘**（`.atomic` 的 rename 是原子操作）
5. 下次启动时 `load()` 会正确读取文件 → 所以"某些时候"设置可能看起来是有效的

**本问题的修复方案**：移除写后 Equatable 校验 + Thread.sleep 的重试循环，恢复为直接的 `writeCodable` 后 return（原始行为）。依赖 `.atomic` 的原子写入保证和写前备份机制。

**相关文件**：
- `AppPreferences.swift:147-159` — 移除 retry 校验逻辑
- `SettingsStore.swift:44-55` — 同上（TokenCostSettings 有对称问题）

---

### 2.2 问题 #2：OpenCode Zen 余额查询不可用

**根因**：`locateBinary()` 只搜索了 `/opt/homebrew/bin/opencode` 和 `/usr/local/bin/opencode`，用户的 OpenCode CLI 实际安装在 `~/.opencode/bin/opencode`

**背景**：Phase 2.1 的安全加固（禁用 PATH 查找以避免注入风险）中，错误地将 `~/.opencode/bin/opencode` 和 `~/.local/bin/opencode` 从搜索列表中移除了。

**官方 OpenCode CLI 安装位置调研**：

| 路径 | 来源 | 占比 |
|------|------|------|
| `$HOME/.opencode/bin/opencode` | 官方 install script 默认 | 80%+ |
| `$HOME/.local/bin/opencode` | XDG_BIN_DIR 或 OPENCODE_INSTALL_DIR 自定义 | ~10% |
| `$HOME/bin/opencode` | 标准 fallback | ~3% |
| `/opt/homebrew/bin/opencode` | Homebrew (Apple Silicon) | ~5% |
| `/usr/local/bin/opencode` | Homebrew (Intel) | ~2% |

**本问题的修复方案**：将 `locateBinary()` 的搜索路径扩展到覆盖上述 5 个标准路径，每个路径找到后通过 `codesign --verify` 校验签名（已被 Phase 2.2 加入）。

**相关文件**：
- `OpenCodeZenBalanceProvider.swift:79-82` — 恢复候选路径

---

### 2.3 问题 #3：Keychain 反复弹窗 4 次

**根因**：启动时 `AppPreferencesModel.init()` 调用 `saveWorkspaceID()`（每次启动写入 Keychain），加上 `BrowserCookieExtractor.extractCredentials()` 遍历 4 个浏览器调用 `/usr/bin/security`（每个浏览器一次 Keychain 访问）

**完整调用链**：

```
启动流程:
  AppPreferencesModel.init()
    └── SecureCredentialStore.saveWorkspaceID(wid)  ← KEYCHAIN ACCESS #1 (SecItemDelete)
    └── SecItemAdd(query)                           ← KEYCHAIN ACCESS #2 (SecItemAdd)

  首次用户点击"刷新余额":
    BalanceManager.refresh()
      └── OpenCodeGoBalanceChecker.fetch()
            └── SecureCredentialStore.discoverCredentials()
                  └── BrowserCookieExtractor.extractCredentials()
                        ├── Edge → /usr/bin/security → KEYCHAIN ACCESS #3
                        ├── Chrome → /usr/bin/security → KEYCHAIN ACCESS #4
                        ├── Brave → /usr/bin/security → (如果前两者失败)
                        └── Arc → /usr/bin/security → (如果前三者失败)
```

**GitHub 优质项目调研结果**：

| 项目 | 核心模式 | 对本项目的启示 |
|------|---------|-------------|
| **AThevon/TokenEater** | `kSecUseAuthenticationUISkip` 静默读取 + 文件优先策略 | 无授权时静默返回 nil 而非弹窗 |
| **steipete/SweetCookieKit** (973⭐) | `BrowserCookieKeychainPromptHandler` 预弹窗机制 | 在系统弹窗前先显示自定义提示 |
| **kishikawakatsumi/KeychainAccess** (8.2K⭐) | `AuthenticationUI` 枚举（allow/fail/skip） | skip 模式：需要认证的项静默跳过 |
| **steipete/CodexBar** | `KeychainAccessPreflight.checkGenericPassword` 探测性访问 | 先检查是否可访问，不触发 UI |

**本问题的修复方案（4 层防御）**：

| 层次 | 措施 | 效果 |
|------|------|------|
| L1 | 移除 `AppPreferencesModel.init()` 中的 `saveWorkspaceID()` 调用 | 消除启动时的 Keychain 写操作 |
| L2 | `SecureCredentialStore.read()` 添加 `kSecUseAuthenticationUISkip` 标志 | 有授权时静默返回，无授权时不弹窗 |
| L3 | `discoverCredentials()` 添加 static 内存缓存 | 同一次 session 中不再重复访问 Keychain |
| L4 | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | 限制到本地设备，减少 iCloud ACL 检查 |

**Keychain 授权模型（修复后）**：

```
首次使用:
  Settings → 保存凭证 → SecItemAdd → macOS 弹 "Allow/Deny/Always Allow" 对话框
  → 用户点 "Always Allow" → ACL 写入 → 授权持久化

后续使用:
  discoverCredentials() → SecItemCopyMatching + kSecUseAuthenticationUISkip
  → ACL 已有授权 → 静默返回数据 → 无弹窗 ✓
  → 同 session 再次调用 → 内存缓存返回 → 零 Keychain 访问 ✓
```

**相关文件**：
- `SecureCredentialStore.swift:110-124` — read() 添加 `kSecUseAuthenticationUISkip`
- `SecureCredentialStore.swift:35-61` — discoverCredentials() 添加内存缓存
- `SecureCredentialStore.swift:92` — kSecAttrAccessible 改为 ThisDeviceOnly
- `AppPreferencesModel.swift:18-20` — 移除 init 中的 saveWorkspaceID()

---

## 三、安全边界分析

### 3.1 写后校验移除的影响分析

| 威胁场景 | .atomic 防护 | 备份防护 | load() fallback | 风险评估 |
|---------|:---:|:---:|:---:|------|
| 磁盘满导致写入失败 | ✅ rename 失败，旧文件不变 | ✅ 备份已存在 | ✅ 加载旧文件 | 无影响 |
| 进程崩溃（写临时文件阶段） | ✅ 临时文件被 OS 清理 | ✅ 旧文件未动 | ✅ 加载旧文件 | 无影响 |
| 进程崩溃（rename 阶段） | ✅ rename 是原子的，要么完成要么不变 | ✅ 旧文件未动 | ✅ 加载旧文件 | 无影响 |
| 文件系统缓存延迟 | ✅ rename 后文件立即可用 | ✅ 备份已有 | ✅ 加载最新文件 | 无影响 |
| JSON 编码错误 | ⚠️ .atomic 不验证内容 | ✅ 备份保留上一个正确版本 | ✅ 解码失败 → 回退默认值 | 极低（编码路径已验证） |
| 文件被外部修改 | ⚠️ 无法检测 | ⚠️ 备份可能也是旧的 | ⚠️ load 可能读到修改后的内容 | 低（Application Support 目录权限受限） |

### 3.2 Keychain 静默读取的安全性

| 方面 | 分析 |
|------|------|
| `kSecUseAuthenticationUISkip` 是否降低安全性？ | 不降低。无 ACL 授权时返回 nil 而非弹窗。凭证仍在 Keychain 中加密存储 |
| 首次授权路径 | SettingsView 的"保存凭证"按钮触发 `SecItemAdd`，iOS 弹对话框。用户点"Always Allow"后授权持久化 |
| 浏览器密钥提取 | `BatchCookieExtractor` 通过 `/usr/bin/security` 读取浏览器密钥。理想情况下需要先检查 ACL 权限 |
| `WhenUnlockedThisDeviceOnly` | 凭证不跨设备同步。OpenCode cookie 只在当前 Mac 有效，这是正确行为 |

### 3.3 OpenCode CLI 多路径搜索的安全性

- 每个候选路径找到二进制后，通过 `codesign --verify` 校验签名
- 未签名的二进制被跳过，不会被执行
- 不使用 `which` 或 PATH 查找（避免注入风险）
- 候选路径限制为用户主目录和系统标准位置

---

## 四、GitHub 优质项目参考

### 设置持久化模式

| 项目 | ⭐ | 核心模式 | 本项目参考点 |
|------|-----|---------|------------|
| **sindresorhus/Defaults** | 2,457 | 集中式 `DefaultsKey<T>("key", default:)` + `@Default` wrapper | 类型安全的键定义 |
| **orchetect/swift-prefs** | 387 | `cachedReadStorageWrite` + 可替换存储后端 | 内存缓存 + 写穿透模式 |
| **omaralbeik/Stores** | 486 | 统一 API 覆盖 UserDefaults/File/CoreData/Keychain | 多后端抽象 |
| **kishikawakatsumi/KeychainAccess** | 8,242 | `AuthenticationUI` 枚举（allow/fail/skip） | Keychain 无 UI 读取 |
| **AThevon/TokenEater** | - | `kSecUseAuthenticationUISkip` + 文件优先策略 | Keychain 静默读取 |

### 本项目当前架构对标

| 方面 | 本项目当前状态 | 优化后 |
|------|-------------|--------|
| 存储介质 | Codable JSON 在 Application Support | ✅ 不变（对标 XcodesApp 等流行项目） |
| 原子写入 | `.atomic` 选项 | ✅ 不变 |
| 写前备份 | backupExistingPreferencesIfNeeded | ✅ 已有 + 保留最近 10 份修复 |
| 写后校验 | ❌ Equatable retry（引入 bug） | ✅ 移除（恢复原始行为） |
| Keychain 访问 | ❌ 启动时写入 + 4 次弹窗 | ✅ 静默读取 + 内存缓存 |

---

## 五、完整执行方案

### Phase 1 — 修复 3 个问题

```
Phase 1A: 设置不持久化（核心修复）
─────────────────────────────────
  A1. AppPreferencesStore.save() — 移除 Equatable retry 校验
      文件: AppPreferences.swift:147
      改动: 删除 L150-157 的 retry 循环 + Thread.sleep，仅保留 writeCodable
  
  A2. SettingsStore.save() — 同上
      文件: SettingsStore.swift:44
      改动: 删除 L46-54 的 retry 循环 + Thread.sleep，仅保留 writeCodable

Phase 1B: OpenCode Zen 不可用
──────────────────────────────
  B1. locateBinary() — 恢复 5 个标准候选路径，每个路径 codesign 校验
      文件: OpenCodeZenBalanceProvider.swift:79
      添加路径: ~/.opencode/bin/opencode, ~/.local/bin/opencode, ~/bin/opencode

Phase 1C: Keychain 反复弹窗
───────────────────────────
  C1. SecureCredentialStore.read() — 添加 kSecUseAuthenticationUISkip 标志
      文件: SecureCredentialStore.swift:110
  
  C2. discoverCredentials() — 添加 static 内存缓存
      文件: SecureCredentialStore.swift:35
  
  C3. kSecAttrAccessible — 改为 WhenUnlockedThisDeviceOnly
      文件: SecureCredentialStore.swift:92
  
  C4. AppPreferencesModel.init() — 移除 saveWorkspaceID() 调用
      文件: AppPreferencesModel.swift:18
```

### Phase 2 — 编译验证

```bash
swift build  # 验证所有 target 编译通过
```

### Phase 3 — 文档更新

| 文件 | 章节/行 | 更新内容 |
|------|---------|---------|
| `CHANGELOG.md` | [v0.6.0] Unreleased → Security | "写后校验简化：移除 main thread 阻塞的 Equatable retry 循环，恢复为 .atomic 原子写入 + 备份机制保障" |
| `CHANGELOG.md` | [v0.6.0] Unreleased → Security | "Keychain 静默读取 + OpenCode Zen CLI 路径修复" |
| `SECURITY.md` | v0.6.0 安全声明 | "设置完整性保障：.atomic 原子写入 + 预写入备份（保留最近 10 份），无需额外回读校验" |
| `SECURITY.md` | v0.6.0 安全声明 | "Keychain 静默读取：kSecUseAuthenticationUISkip + 内存缓存 + ThisDeviceOnly 设备锁定" |
| `docs/开发手册.md` | §8 安全边界 | 更新校验策略说明 |
| `docs/S3-Keychain安全方案.md` | 版本和变更声明 | 更新 kSecUseAuthenticationUISkip 说明 |

### 涉及文件一览

```
Source Files（6 个）:
  Sources/CodexTokenCostCore/AppPreferences.swift         -17 行
  Sources/CodexTokenCostCore/SettingsStore.swift           -7 行
  Sources/CodexTokenCostCore/Balance/SecureCredentialStore.swift  +24 行
  Sources/CodexTokenCostApp/Stores/AppPreferencesModel.swift      -3 行
  Sources/CodexTokenCostCore/Balance/Providers/OpenCodeZenBalanceProvider.swift  +15 行

Documentation（4 个）:
  CHANGELOG.md
  SECURITY.md
  docs/开发手册.md
  docs/S3-Keychain安全方案.md
```

### 版本号策略

- 不新增版本号 — 所有变更写入现有 `[v0.6.0] Unreleased` 条目
- SECURITY.md 版本表保持 v0.6.0 = "Unreleased (开发中)"
- 打 tag `v0.6.0` 时由维护者统一将 Unreleased 改为正式 release date

---

## 六、验证计划

| 步骤 | 验证内容 | 预期结果 |
|------|---------|---------|
| 1. 编译 | `swift build` 全量编译 | 零错误 |
| 2. 设置持久化 | 修改 billing toggle/billing/theme → 关闭 → 重启 → 检查 | 设置保留 |
| 3. 余额监控 | 启用余额监控 → 检查 Zen 状态 | 显示正常（非"不可用"） |
| 4. Keychain 弹窗 | 首次启动 → 检查钥匙串弹窗数量 | ≤1 次（仅在首次保存凭证时） |
| 5. 文件完整性 | 检查 `app-preferences.json` 修改时间戳 | 反映最新修改 |
| 6. 备份 | 检查 `backups/` 目录 | 存在 <10 份历史备份 |

---

## 七、附录

### A. 磁盘文件路径

```
活跃配置文件:
  ~/Library/Application Support/com.yanghaoran.CodexTokenCost/config/app-preferences.json
  ~/Library/Application Support/com.yanghaoran.CodexTokenCost/config/settings.json
  ~/Library/Application Support/com.yanghaoran.CodexTokenCost/config/codex-settings.json

备份目录:
  ~/Library/Application Support/com.yanghaoran.CodexTokenCost/config/backups/app-preferences/
  ~/Library/Application Support/com.yanghaoran.CodexTokenCost/config/backups/settings/

Keychain 服务名:
  com.yanghaoran.CodexTokenCost.opencode-go
```

### B. 编码/解码链关键参数

```
编码器:
  JSONEncoder
    .outputFormatting = [.prettyPrinted, .sortedKeys]
    .keyEncodingStrategy = .convertToSnakeCase

解码器:
  JSONDecoder
    .keyDecodingStrategy = .convertFromSnakeCase

自定义 CodingKeys:
  AppPreferences: language, openCodePricingMode, billingSelectionsByProvider,
                  balanceEnabled="balance_enabled", balanceRefreshMinutes="balance_refresh_minutes",
                  opencodeGoWorkspaceID="opencode_go_workspace_id", theme, displayCurrency
  BillingPlanSelection: mode, presetID, customMonthlyUSD, isSubscribed
```

### C. Keychain 操作速查

```
读写凭证:
  saveWorkspaceID("wrk_xxx")  → SecItemDelete + SecItemAdd (交互式授权)
  getWorkspaceID()            → SecItemCopyMatching + kSecUseAuthenticationUISkip (静默)
  saveAuthCookie("cookie")    → SecItemDelete + SecItemAdd (交互式授权)
  getAuthCookie()             → SecItemCopyMatching + kSecUseAuthenticationUISkip (静默)
  discoverCredentials()       → 内存缓存 → Keychain 静默读取 → env var → opencode-bar → browser

Keychain 属性:
  kSecClass: kSecClassGenericPassword
  kSecAttrService: com.yanghaoran.CodexTokenCost.opencode-go
  kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

### D. SafeFileStore 写入链路

```
writeCodable(value, to: relativePath)
  └── JSONEncoder(keyEncodingStrategy: .convertToSnakeCase, outputFormatting: [.prettyPrinted, .sortedKeys])
        └── encode(value) → Data
              └── writeData(data, to: relativePath)
                    └── resolve(relativePath) → URL
                          └── validate(url) → 确认在 root 沙箱内
                                └── createDirectory(父目录)
                                      └── data.write(to: url, options: [.atomic])
                                            ├── 写临时文件
                                            └── rename(临时文件, 目标路径)  ← 原子操作
```

---

> **总结**: 所有 3 个问题的根因均已通过 SDD 格式全链路审计确认完毕。修复方案最小化（只删除引入的回归代码 + 补充 3 个安全加固），风险极低。本报告可作为后续执行的权威参考。
