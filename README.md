# Token Cost App — OC Codex

[![Latest Release](https://img.shields.io/github/v/release/blackkcold/Token-Cost-App-OC-Codex?label=latest)](https://github.com/blackkcold/Token-Cost-App-OC-Codex/releases/tag/v1.1.2)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0+-lightgrey)]()
[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)]()

[English](#english) | [中文](#中文)

---

## English

A native macOS dashboard for visualizing token usage and cost across AI coding tools. OpenCode/Codex source analysis is local and read-only; the optional Relay feature sends only end-to-end encrypted balance snapshots between paired clients.

### System Architecture

This public repository contains two clients that can optionally use a separately maintained Private Relay:

| System | Directory | Role |
|--------|-----------|------|
| **macOS desktop app** | `Sources/` | Local data aggregation, provider balance querying, relay client, local state |
| **Android companion app** | `android/` | Pairing UX, relay client, balance display and state recovery |
| **Private Relay** | Separate private repository | Opaque device-to-device forwarding; server implementation and deployment are not public |

The macOS app is the data owner. The optional Android companion pairs through Protocol v1 and a Private Relay that forwards opaque E2EE envelopes. Production Relay source, deployment configuration and hostname are not part of this repository. The public protocol is maintained separately as **Token-Cost-Relay-Contract**; this repository vendors its test-vector snapshot under `Resources/RelayContract/v1/`.

### Why Token Cost App?

AI coding tools charge by token — but most developers have no idea what they're actually spending. This app gives you:
- **Unified cost view** across OpenCode, Codex/ChatGPT, MiniMax, and Xiaomi MiMo
- **Real subscription cost tracking** — not just API estimates, but what you actually pay
- **Local source analysis** — OpenCode/Codex source files stay local; optional Relay traffic is explicitly E2EE

### Features

- **Dual-Source Aggregation** — Reads OpenCode SQLite databases and Codex JSONL session files simultaneously; no manual export required
- **Cost Analytics** — Unified billing model: total cost = enabled fixed subscription fees + pay-as-you-go API estimates; supports official plans for OpenCode Go/Zen, ChatGPT Plus/Pro/Business Codex, MiniMax Token Plan, Xiaomi MiMo Token Plan, plus custom DIY monthly fees
- **OpenCode Skills Panel** — Discover global skills, validate SKILL.md manifests, visualize permission rule chains, and view 8-agent availability matrix; multi-criteria filtering (source/status/tags), grouped sections, Liquid Glass UI
- **Visual Dashboard** — Unified 7/30-day daily trend charts, responsive 52-week usage heatmap, provider cost-efficiency rankings, model distribution pie charts, stacked bar charts
- **Menu Bar Widget** — Combined monthly cost overview card + 7-day OpenCode daily usage mini trend chart — no need to open the main window
- **Bilingual UI** — Switch between Chinese and English; terminology stays consistent
- **Theme & Appearance** — Choose Ocean, Forest, Sunset, or Violet independently from System, Light, or Dark appearance
- **CNY/USD Toggle** — All prices dynamically switch with currency; custom monthly fees auto-convert
- **Balance Monitoring** — Real-time balance queries for OpenCode Go / Codex / OpenCode Zen / DeepSeek / Ollama Cloud, with validated encrypted Cookie caching, browser/profile fallback, and multi-window quota visualization
- **Relay Analytics 1.1** — Optional E2EE transport for overview, cache, cost, usage, model distribution, trend, and heatmap sections with bounded RFC 1950 decompression and encrypted Android caching
- **Responsive Settings Panel** — Module-based collapsible settings with adaptive horizontal layout for faster desktop scanning
- **Desktop-Friendly Window Behavior** — Closing the main window hides the Dock icon while keeping the MenuBar workflow active
- **Update Checker** — Silent check on launch + manual trigger; auto-downloads updates
- **Offline-first** — Core analysis runs locally; update checks and explicitly enabled Provider/Relay features use documented network paths
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

#### Android Companion App

The repo also contains an Android companion app (`android/`) — a Flutter-based **Balance Monitor** that pairs with the macOS app via QR code and shows AI-provider balances on your phone.

```bash
cd android
flutter pub get
flutter analyze
flutter test

# Package release artifacts (APK + AAB) into App-Builds/vA.BCD.E-<UTC minute>/android/
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"  # 脚本会自动回退识别已安装的 JDK 17
export RELAY_BASE_URL="${RELAY_BASE_URL:?Set the protected HTTPS Relay endpoint}"
bash script/build_android_release.sh release
```

> **打包策略**：不打包 QA 或 Debug 版。归档到 `App-Builds/` 的产物均为带签名正式版（`release` 模式），供正式环境手动测试。Android 签名使用本地 `key.properties` + 被忽略的 `.jks`，不依赖 CI 注入；产物手动上传到 macOS 的 tag Release（`gh release upload <macOS-tag> App-Builds/vA.BCD.E-<UTC minute>/android/*`）。CI 仅在 `.github/workflows/ci.yml` 中运行 Android `flutter analyze` / `flutter test`，不构建或上传 Android 产物。

See [android/README.md](android/README.md) for details.

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
- Configure OpenCode Go credentials (Workspace ID + Auth Cookie) and Ollama Cloud Cookie; both use encrypted app-local caching and validated fallback across Edge / Chrome / Brave / Arc profiles
- Open the built-in read-only pricing reference document to view current billing rates offline
- Choose an accent palette and independently follow the system appearance or force Light/Dark mode
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
├── android/                   # Android companion app (Flutter Balance Monitor)
├── docs/                      # Architecture docs & dev manual
├── script/                    # Build & run scripts
├── release/                   # Release metadata (versions.json) — binaries live in workspace App-Builds/
└── .github/workflows/         # CI/CD
```

> **Build output convention**: Release binaries are archived to the workspace-level `App-Builds/` directory (exact-case `App-Builds`) under timestamped platform versions: macOS uses `App-Builds/vX.Y.Z-YYYYMMDD-HHMM/macos/`, while Android uses its independent `App-Builds/vA.BCD.E-YYYYMMDD-HHMM/android/` version. Local development snapshots keep the collision-safe seconds + PID suffix; `App-Builds/latest/<platform>` remains platform-scoped. macOS release is built by CI; Android release is built locally and manually uploaded to the macOS tag Release. `release/versions.json` remains repo metadata and stores the canonical macOS version plus the timestamped zip filename.

See [dev manual](docs/开发手册.md) and [architecture diagram](docs/架构逻辑链图.md) for details.

#### Relay Development

Production Relay implementation and deployment remain private. Public builds and tests do not depend on the Private Relay repository. Internal development uses sibling Public App, Private Relay and Public Contract repositories; both Debug clients must be launched with the same explicit `RELAY_BASE_URL`.

### License

MIT License — see [LICENSE](LICENSE)

---

## 中文

一款原生 macOS 仪表盘应用，用于可视化 AI 编程工具的 token 用量与费用。OpenCode/Codex 源数据分析保持本地只读；可选 Relay 功能只在已配对客户端之间传输端到端加密的余额快照。

### 系统架构

本 Public Repository 包含两个客户端，并可选连接独立维护的 Private Relay：

| 系统 | 目录 | 职责 |
|------|------|------|
| **macOS 桌面端** | `Sources/` | 本地数据聚合、Provider 余额查询、中继客户端、本地状态 |
| **安卓配套 App** | `android/` | 配对交互、中继客户端、余额展示与状态恢复 |
| **Private Relay** | 独立 Private Repository | 不透明设备转发；服务端实现和部署不公开 |

macOS 桌面端是数据所有者。Android 通过 Protocol v1 和 Private Relay 完成配对及余额展示；Relay 只转发 E2EE 不透明信封。Production Relay 源码、部署配置和真实地址不在本仓库。Public Protocol 单独维护为 **Token-Cost-Relay-Contract**，本仓库仅在 `Resources/RelayContract/v1/` 保存测试向量快照。

### 为什么需要它？

AI 编程工具按 token 计费，但大多数开发者不清楚自己到底花了多少钱。这个 App 帮你：
- **统一费用视图** — OpenCode、Codex/ChatGPT、MiniMax、小米 MiMo 一目了然
- **真实订阅成本追踪** — 不是 API 估算，而是你实际支付的订阅费
- **本地源数据分析** — OpenCode/Codex 源文件不离开电脑；可选 Relay 流量明确使用 E2EE

### 功能特性

- **双源统计** — 同时读取 OpenCode (SQLite) 和 Codex (JSONL Session) 数据；无需手动导出
- **费用分析** — 统一计费模型：总成本 = 已启用固定订阅费用 + 未订阅部分 API 估算成本；支持 OpenCode Go/Zen、ChatGPT Plus/Pro/Business Codex、MiniMax Token Plan、小米 MiMo Token Plan 官方方案，并可用 DIY 月费应对价格变更
- **OpenCode Skills 只读面板** — 发现全局 skill 目录，校验 SKILL.md manifest，可视化 permission 规则链与 8-agent 可用性矩阵；多维度过滤（来源/状态/标签），Section 分组列表，Liquid Glass 毛玻璃 UI
- **可视化仪表盘** — 统一 7/30 日趋势图、过去 52 周响应式用量热力图、Provider 性价比排行、模型分布饼图、堆叠条形图
- **菜单栏速览** — 综合月费概览卡片 + 最近 7 天 OpenCode 日用量迷你趋势图，无需打开主窗口
- **中英双语** — 界面可在中文 / 英语之间切换，术语保持一致
- **主题与外观** — 海洋蓝、森林绿、日落橙、紫罗兰 4 种主题色，可独立选择跟随系统、浅色或深色外观
- **人民币/美元计价切换** — 所有价格展示随币种动态切换，自定义月费自动换算
- **余额监控** — 支持 OpenCode Go / Codex / OpenCode Zen / DeepSeek / Ollama Cloud 余额实时查询；Cookie 优先从内存与 App 本地 AES 加密缓存读取，失效时自动验证 Chrome/Edge/Brave/Arc 的后续候选，不触发 Keychain 授权弹窗
- **Relay Analytics 1.1** — 可选 E2EE 传输总览、缓存、成本、用量、模型分布、趋势与热力图；Android 使用有界 RFC 1950 解压和加密短期缓存
- **响应式设置页** — 模块化折叠设置面板，短控件采用横向自适应布局，桌面端浏览更高效
- **桌面窗口行为优化** — 关闭主窗口后自动隐藏 Dock 图标，保留 MenuBar 工作流
- **版本更新检查** — 启动时静默检查 + 手动触发，自动下载更新包
- **离线优先** — 核心分析本地运行；更新检查及显式启用的 Provider/Relay 功能使用文档列明的网络路径
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

#### 安卓配套 App

仓库还包含一个安卓配套 App（`android/`）——一个基于 Flutter 的**余额监控**应用，通过扫描二维码与 macOS 桌面端配对，在手机上查看各 AI Provider 的余额。

```bash
cd android
flutter pub get
flutter analyze
flutter test

# 打包 release 产物（APK + AAB）到 App-Builds/vA.BCD.E-<UTC 分钟>/android/
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"  # 脚本会自动回退识别已安装的 JDK 17
export RELAY_BASE_URL="${RELAY_BASE_URL:?请先设置受保护的 HTTPS Relay Endpoint}"
bash script/build_android_release.sh release
```

> **打包策略**：不打包 QA 或 Debug 版。归档到 `App-Builds/` 的产物均为带签名正式版（`release` 模式），供正式环境手动测试。Android 签名使用本地 `key.properties` + 被忽略的 `.jks`，不依赖 CI 注入；产物手动上传到 macOS 的 tag Release（`gh release upload <macOS-tag> App-Builds/vA.BCD.E-<UTC 分钟>/android/*`）。CI 仅在 `.github/workflows/ci.yml` 中运行 Android `flutter analyze` / `flutter test`，不构建或上传 Android 产物。

详见 [android/README.md](android/README.md)。

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
- 配置 OpenCode Go 凭证（Workspace ID + Auth Cookie）和 Ollama Cloud Cookie；支持 App 本地加密缓存及 Edge / Chrome / Brave / Arc 多 Profile 验证兜底
- 打开内置只读计费参考文档，离线查看当前内置价格口径
- 独立选择主题色，并设置跟随系统、固定浅色或固定深色外观
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
├── android/                   # 安卓配套 App（Flutter 余额监控）
├── docs/                      # 文档
├── script/                    # 构建脚本
├── release/                   # 发布元数据（versions.json）——二进制产物在工作区 App-Builds/
└── .github/workflows/         # CI/CD
```

> **构建产物约定**：发布二进制归档到工作区级 `App-Builds/` 目录（精确大小写 `App-Builds`）。macOS 使用 `App-Builds/vX.Y.Z-YYYYMMDD-HHMM/macos/`，Android 使用独立版本 `App-Builds/vA.BCD.E-YYYYMMDD-HHMM/android/`；本地开发快照继续使用秒级时间戳 + PID 防碰撞，`App-Builds/latest/<platform>` 按平台隔离。macOS 正式产物由 CI 构建；Android 正式产物在本地构建并手动上传到 macOS 的 tag Release。`release/versions.json` 仍是仓库元数据，其中 macOS `version` 保持纯版本，`file` 记录带时间戳 zip 文件名。

详见 [开发手册](docs/开发手册.md) 和 [架构逻辑链图](docs/架构逻辑链图.md)。

#### Relay 开发

Production Relay 实现与部署保持私有，Public App 的构建和测试不依赖 Private Relay Repository。内部开发采用 Public App、Private Relay、Public Contract 三个 sibling repositories；两个 Debug 客户端必须显式注入同一个 `RELAY_BASE_URL`。

### 许可证

MIT License - 详见 [LICENSE](LICENSE)
