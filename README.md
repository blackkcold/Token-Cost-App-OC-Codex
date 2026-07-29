# Token Cost App — OC Codex

[![Latest Release](https://img.shields.io/github/v/release/blackkcold/Token-Cost-App-OC-Codex?label=latest)](https://github.com/blackkcold/Token-Cost-App-OC-Codex/releases/tag/v1.0.1)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0+-lightgrey)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)]()

[English](#english) | [中文](#中文)

---

## English

A native macOS dashboard for visualizing token usage and cost across AI coding tools. Supports **OpenCode** (SQLite) and **Codex** (JSONL session) as dual data sources — all local, read-only, and privacy-first.

> **Latest**: [v1.0.1](https://github.com/blackkcold/Token-Cost-App-OC-Codex/releases/tag/v1.0.1) — Ollama Cloud cache read estimation, balance refresh optimization, Window scene simplification

### What's New in v1.0.1

- **Ollama Cloud cache read estimation** — Auto-enables estimated cache reads for `deepseek-v4-flash` / `deepseek-v4-pro` models under `ollama-cloud` provider, using `estimatedCacheRead = input × (rate / (1−rate))`. Cache section card title switches to "Cache (estimated)" variant with independent `mint` trend line. Estimates don't affect billing.
- **Balance refresh performance** — Sentinel refactored to sentinel + counting mode, no longer forced 45s wait. `AuthTokenProvider.token(for:)` wrapped in `Task.detached`. Merged `@Published` assignments reduce SwiftUI redraws from 7 to 6 per cycle.
- **Window scene simplification** — Main scene changed from `WindowGroup(id: "main")` to `Window(id: "main")` — system guarantees single window instance. `WindowOpeningSupport` simplified to single `openWindow(id:openWindow:)` function.
- **Menu bar UI improvements** — Balance title row now has `arrow.clockwise` refresh button with spinner. Settings/quit buttons changed to icon form.
- **Bug fixes** — Ollama Cloud cache hit rate always 0%, balance refresh forced 45s minimum, ForEach ID non-unique crash risk, window singleton guard missing, Dock icon sync race condition.

### What's New in v1.0.0

- **Credential storage upgrade** — Migrated from macOS Keychain to local AES-256-GCM encrypted storage (`LocalEncryptedCredentialStore`), eliminating Keychain permission prompts during development builds.
- **Auto credential bootstrap** — On launch, automatically decrypts Go and Ollama credentials from browser cookies into memory; falls back to Keychain silently. Switch to "Keychain Only" mode in Settings.
- **Legacy Keychain import** — Settings now offers a one-click "Import legacy Keychain" button to migrate existing credentials to local encrypted storage.
- **Performance** — `DetailView` analytics computation moved off the main thread via async `Task.detached`, with loading placeholder states for large payloads.

### Why Token Cost App?

AI coding tools charge by token — but most developers have no idea what they're actually spending. This app gives you:
- **Unified cost view** across OpenCode, Codex/ChatGPT, MiniMax, and Xiaomi MiMo
- **Real subscription cost tracking** — not just API estimates, but what you actually pay
- **Local-only, zero telemetry** — no data leaves your machine

### Features

- **Dual-Source Aggregation** — Reads OpenCode SQLite databases and Codex JSONL session files simultaneously; no manual export required
- **Cost Analytics** — Unified billing model: total cost = enabled fixed subscription fees + pay-as-you-go API estimates; supports official plans for OpenCode Go/Zen, ChatGPT Plus/Pro/Business Codex, MiniMax Token Plan, Xiaomi MiMo Token Plan, plus custom DIY monthly fees
- **OpenCode Skills Panel** — Discover global skills, validate SKILL.md manifests, visualize permission rule chains, and view 8-agent availability matrix; multi-criteria filtering (source/status/tags), grouped sections, Liquid Glass UI
- **Visual Dashboard** — Unified 7/30-day daily trend charts, responsive 52-week usage heatmap, provider cost-efficiency rankings, model distribution pie charts, stacked bar charts
- **Menu Bar Widget** — Combined monthly cost overview card + 7-day OpenCode daily usage mini trend chart — no need to open the main window
- **Bilingual UI** — Switch between Chinese and English; terminology stays consistent
- **Multi-Theme** — Bay Blue, Forest Green, Twilight Orange, Aurora Purple
- **CNY/USD Toggle** — All prices dynamically switch with currency; custom monthly fees auto-convert
- **Balance Monitoring** — Real-time balance queries for OpenCode Go / Codex / OpenCode Zen / DeepSeek / Ollama Cloud, with multi-window quota and balance-entry visualization (Ollama gated under Developer Mode, requires session cookie stored in system Keychain; supports browser-based auto-import from Chrome/Edge/Brave/Arc and one-click connection testing)
- **Responsive Settings Panel** — Module-based collapsible settings with adaptive horizontal layout for faster desktop scanning
- **Desktop-Friendly Window Behavior** — Closing the main window hides the Dock icon while keeping the MenuBar workflow active
- **Update Checker** — Silent check on launch + manual trigger; auto-downloads updates
- **Offline & Local** — Runs entirely on your machine; update checks only anonymously pull GitHub's public Release API
- **Read-Only Safe** — Never modifies your source data

### Quick Start

#### Requirements

- macOS 14.0 (Sonoma) or later

#### Download

Download the `.zip` or `.dmg` from [GitHub Releases](../../releases). For `.dmg`, open it and drag the app to `/Applications`. For `.zip`, unzip and run the `.app`.

#### Build from Source

```bash
git clone https://github.com/blackkcold/Token-Cost-App-OC-Codex.git
cd Token-Cost-App-OC-Codex

# Build only
bash script/build_and_run_codex.sh build

# Build & run
bash script/build_and_run_codex.sh run

# Swift compile only
swift build
```

### Configuration

On launch, the app auto-scans these default locations:

| Source   | Type            | Default Path                                                              |
|----------|-----------------|---------------------------------------------------------------------------|
| OpenCode | SQLite Database | `~/.local/share/opencode/`, `~/Library/Application Support/OpenCode/`    |
| Codex    | JSONL Sessions  | `~/.codex/sessions/`, `~/.codex/archived_sessions/`                      |

In the **Settings panel** you can:
- Add custom scan directories or database files
- Adjust scan depth and snapshot retention
- Switch UI language and OpenCode pricing mode on the overview page
- Manage provider billing plans: OpenCode Go / Zen, ChatGPT Plus / Pro / Business Codex, MiniMax Token Plan, Xiaomi MiMo Token Plan, or enter custom USD monthly fees
- Configure OpenCode Go credentials (Workspace ID + Auth Cookie) and Ollama Cloud cookie with "Test Connection" buttons; both support auto-import from Edge / Chrome / Brave / Arc where available
- Open the built-in read-only pricing reference document to view current billing rates offline
- Switch UI theme
- Manage Codex session sources

### Tech Stack

- **Language**: Swift 6.0
- **UI**: SwiftUI + AppKit
- **Build**: Swift Package Manager
- **Database**: SQLite3 (system built-in)

### Project Structure

```
Token-Cost-App-OC-Codex/
├── Sources/                   # Source code
│   ├── CodexTokenCostCore/    # Core module (models, analytics, discovery)
│   ├── CodexTokenCostApp/     # Main app (SwiftUI views, stores, entry)
│   └── CodexTokenCostHelper/  # Helper process (CLI Codex session collector)
├── docs/                      # Architecture docs & dev manual
├── script/                    # Build & run scripts
├── release/                   # Release artifacts + versions.json
└── .github/workflows/         # CI/CD
```

See [dev manual](docs/开发手册.md) and [architecture diagram](docs/架构逻辑链图.md) for details.

### License

MIT License — see [LICENSE](LICENSE)

---

## 中文

一款原生 macOS 仪表盘应用，用于可视化 AI 编程工具的 token 用量与费用。支持 **OpenCode** (SQLite) 和 **Codex** (JSONL Session) 双数据源，纯本地运行，只读安全。

> **最新版本**: [v1.0.1](https://github.com/blackkcold/Token-Cost-App-OC-Codex/releases/tag/v1.0.1) — Ollama Cloud 缓存读估算、余额刷新优化、Window 场景简化

### v1.0.1 更新

- **Ollama Cloud 缓存读估算** — 对 `ollama-cloud` Provider 下 `deepseek-v4-flash` / `deepseek-v4-pro` 模型自动启用缓存读缺失估算，使用 `estimatedCacheRead = input × (rate / (1−rate))` 公式。缓存区卡片标题切换为"缓存（含估算）"变体，趋势图 tooltip 追加独立 `mint` 色估算行。估算值不影响计费口径。
- **余额刷新性能优化** — 超时哨兵改为 sentinel + 计数模式，不再强制等待 45s。`AuthTokenProvider.token(for:)` 包装在 `Task.detached` 中。合并 `@Published` 赋值，每个刷新周期 SwiftUI 重绘从 7 次减少到 6 次。
- **Window 场景简化** — 主场景从 `WindowGroup(id: "main")` 改为 `Window(id: "main")`，由系统保证单窗口实例。`WindowOpeningSupport` 简化为单一 `openWindow(id:openWindow:)` 函数。
- **菜单栏 UI 改进** — 余额标题行右侧新增 `arrow.clockwise` 刷新按钮，刷新中显示 spinner。设置/退出按钮改为图标形式。
- **Bug 修复** — Ollama Cloud 缓存命中率始终为 0、余额刷新强制 45s 最短时间、ForEach ID 非唯一崩溃风险、窗口单例守卫缺失、Dock 图标同步竞态。

### v1.0.0 更新

- **凭证存储升级** — 从 macOS Keychain 全面迁移至本地 AES-256-GCM 加密存储，消除开发构建时的 Keychain 授权弹窗。
- **自动凭证引导** — 启动时自动从浏览器解密 Go 和 Ollama 凭证到内存，静默回退 Keychain；可在设置中切换为「仅从 Keychain 读取」。
- **旧 Keychain 导入** — 设置页新增一键「导入旧 Keychain」按钮，将已有凭证迁移到本地加密存储。
- **性能优化** — 详情页 analytics 计算移至后台线程异步执行，大数据 payload 不再卡主线程。

### 为什么需要它？

AI 编程工具按 token 计费，但大多数开发者不清楚自己到底花了多少钱。这个 App 帮你：
- **统一费用视图** — OpenCode、Codex/ChatGPT、MiniMax、小米 MiMo 一目了然
- **真实订阅成本追踪** — 不是 API 估算，而是你实际支付的订阅费
- **纯本地，零遥测** — 所有数据不出你的电脑

### 功能特性

- **双源统计** — 同时读取 OpenCode (SQLite) 和 Codex (JSONL Session) 数据；无需手动导出
- **费用分析** — 统一计费模型：总成本 = 已启用固定订阅费用 + 未订阅部分 API 估算成本；支持 OpenCode Go/Zen、ChatGPT Plus/Pro/Business Codex、MiniMax Token Plan、小米 MiMo Token Plan 官方方案，并可用 DIY 月费应对价格变更
- **OpenCode Skills 只读面板** — 发现全局 skill 目录，校验 SKILL.md manifest，可视化 permission 规则链与 8-agent 可用性矩阵；多维度过滤（来源/状态/标签），Section 分组列表，Liquid Glass 毛玻璃 UI
- **可视化仪表盘** — 统一 7/30 日趋势图、过去 52 周响应式用量热力图、Provider 性价比排行、模型分布饼图、堆叠条形图
- **菜单栏速览** — 综合月费概览卡片 + 最近 7 天 OpenCode 日用量迷你趋势图，无需打开主窗口
- **中英双语** — 界面可在中文 / 英语之间切换，术语保持一致
- **多主题** — 海湾蓝、森林绿、暮光橙、极光紫 4 种主题色
- **人民币/美元计价切换** — 所有价格展示随币种动态切换，自定义月费自动换算
- **余额监控** — 支持 OpenCode Go / Codex / OpenCode Zen / DeepSeek / Ollama Cloud 余额实时查询，并展示多窗口配额与余额条目（Ollama 需在开发者模式下启用，session cookie 存储在系统 Keychain 中；支持从 Chrome/Edge/Brave/Arc 浏览器自动导入和一键测试连接；启动时自动从浏览器解密凭证并缓存到内存，无需每次打开 app 都触发 Keychain 权限弹窗，用户可在设置中切换为「仅从 Keychain 读取」模式）
- **响应式设置页** — 模块化折叠设置面板，短控件采用横向自适应布局，桌面端浏览更高效
- **桌面窗口行为优化** — 关闭主窗口后自动隐藏 Dock 图标，保留 MenuBar 工作流
- **版本更新检查** — 启动时静默检查 + 手动触发，自动下载更新包
- **本地离线** — 纯本地运行；版本更新检查仅匿名拉取 GitHub 公开 Release API，不上传数据
- **只读安全** — 源数据只读访问，不修改任何源数据

### 快速开始

#### 系统要求

- macOS 14.0 (Sonoma) 或更高版本

#### 下载安装

从 [GitHub Releases](../../releases) 页面下载对应版本 `.zip` 或 `.dmg`。`.dmg` 用户可双击打开后拖拽 app 到 `/Applications` 完成安装；`.zip` 解压后直接运行 `.app` 文件。

#### 从源码构建

```bash
git clone https://github.com/blackkcold/Token-Cost-App-OC-Codex.git
cd Token-Cost-App-OC-Codex

# 仅构建 app
bash script/build_and_run_codex.sh build

# 编译并运行
bash script/build_and_run_codex.sh run

# 仅编译
swift build
```

### 配置说明

启动后，应用会自动扫描以下默认位置：

| 来源 | 类型 | 默认路径 |
|------|------|---------|
| OpenCode | SQLite 数据库 | `~/.local/share/opencode/`, `~/Library/Application Support/OpenCode/` |
| Codex | JSONL Session 文件 | `~/.codex/sessions/`, `~/.codex/archived_sessions/` |

可在 **设置面板** 中：
- 添加自定义扫描目录或数据库文件
- 调整扫描深度和快照保留数
- 切换界面语言和总览页 OpenCode 计价口径
- 管理各 Provider 计费方案：OpenCode Go / Zen、ChatGPT Plus / Pro / Business Codex、MiniMax Token Plan、Xiaomi MiMo Token Plan，或输入自定义 USD 月费
- 配置 OpenCode Go 凭证（Workspace ID + Auth Cookie）和 Ollama Cloud Cookie，并用「测试连接」按钮校验当前配置；也支持从 Edge / Chrome / Brave / Arc 自动导入凭证
- 打开内置只读计费参考文档，离线查看当前内置价格口径
- 切换界面主题
- 管理 Codex session 来源

### 技术栈

- **语言**: Swift 6.0
- **UI**: SwiftUI + AppKit
- **构建**: Swift Package Manager
- **数据库**: SQLite3 (系统内置)

### 项目结构

```
Token-Cost-App-OC-Codex/
├── Sources/                   # 源码
│   ├── CodexTokenCostCore/    # 核心模块
│   ├── CodexTokenCostApp/     # 主应用
│   └── CodexTokenCostHelper/  # 辅助进程
├── docs/                      # 文档
├── script/                    # 构建脚本
├── release/                   # 发布产物 + versions.json
└── .github/workflows/         # CI/CD
```

详见 [开发手册](docs/开发手册.md) 和 [架构逻辑链图](docs/架构逻辑链图.md)。

### 许可证

MIT License - 详见 [LICENSE](LICENSE)
