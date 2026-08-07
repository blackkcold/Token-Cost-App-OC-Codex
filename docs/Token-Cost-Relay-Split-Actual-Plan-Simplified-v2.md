# Token Cost App — Relay 安全拆分实际执行方案（简化版 v2）

> **用途**：本文件用于直接交给 OpenCode / Coding Agent 执行本次 Relay 仓库拆分、安全更新、Git/GitHub 操作、跨项目联调、脚本与引用检查、个人信息清理以及最终文档更新。
>
> **基线日期**：2026-08-07
> **执行原则**：先建立正确边界，再做安全修正；本轮避免与拆分无关的重构。
> **目标形态**：Public App + Public Contract + Private Relay。
> **核心要求**：架构尽量简单；Public 不包含真实 Relay 服务端实现；Private 包含完整开发与架构文档；所有项目 README 与关联文档保持同步。

---

# 0. OpenCode 总执行指令

本次任务按以下原则执行：

1. **基于当前真实代码执行，不照搬旧方案中的假设。**
2. 当前 `relay/` 与 `android/` 在调研工作树中均为未跟踪目录，因此优先按“首次建立正确仓库边界”处理。
3. 在确认 canonical/main 仓库真实状态前，不执行：
   - `git filter-repo`
   - force push
   - Git history rewrite
4. `relay/` 不得先提交到 Public App 再删除。
5. 本轮不强拆 Swift Relay Target。
6. 本轮不重构 Node Relay 的 `app.js` / `database.js` / `security.test.js`。
7. 本轮不新增完整 Public RelayMock；公共仓库通过 unit test / contract vectors 保证可测试，真实联调由内部 sibling Private Relay 完成。
8. `Balance/Sync` 与 Relay 是两个不同系统，本轮不得混合迁移。
9. Android Release 中不得向用户显示、允许修改或通过二维码动态指定 Production Relay 地址。
10. Production Relay 地址不得作为明文配置提交进 Public Repository。
11. 所有仓库在提交前执行：
    - Secret Scan
    - Personal Information Scan
    - Absolute Path Scan
    - Broken Reference Scan
12. 三个项目都必须更新 README 与相关文档。
13. Private Relay 必须提供详细的：
    - 架构说明
    - 开发说明
    - 部署说明
    - 安全说明
14. Public App 只保留基本的：
    - 架构说明
    - 开发说明
    - Relay 使用说明
    - 安全边界说明
15. 所有脚本、CI、README、docs、配置、测试、路径引用必须在拆分后进行一次全量校验。
16. 尽可能清除个人姓名、邮箱、本机用户名、绝对路径、工号/账号、开发机目录等个人信息。
17. 不把“Relay 地址隐藏”或“Private Repo”当作核心密码学安全控制。系统仍必须依赖 E2EE、认证、防重放、授权和安全部署。
18. Public Contract 仅包含 Public App 客户端正常运行所必需的 Client-facing Protocol；Admin、Internal、Maintenance、Deployment、Database、Rate-limit implementation、Replay implementation 等服务端接口和实现不得进入 Public Contract。

---

# 1. 实际调研结论

基于当前调研结果，本轮采用以下真实基线。

## 1.1 Git 状态

当前调研工作树：

```text
relay/      → untracked
android/    → untracked
```

因此：

```text
不是：
Public Relay → 再拆到 Private

而是：
首次提交前
直接建立正确 Public / Private 边界
```

本轮默认：

- 不做 Relay Git 历史迁移；
- 不做 Git history rewrite；
- 不做 MIT 历史授权清理；
- 不允许 Relay 服务端源码进入 Public App。

执行前仍必须再次验证 canonical repository：

```bash
git ls-files relay/
git log --all -- relay/
git ls-files android/
git log --all -- android/
```

如果 canonical repository 与调研工作树不同，停止 history 相关操作并单独报告。

---

## 1.2 Swift Relay 当前真实结构

当前 Relay Client 仍在：

```text
Sources/CodexTokenCostCore/Balance/Relay/
```

存在真实 Core 耦合：

```text
BalanceRelayCoordinator
    → BalanceManager

BalanceRelayIdentityStore
    → TokenCostPaths
```

因此本轮：

```text
不新增：
CodexTokenCostRelayProtocol Target
CodexTokenCostRelayClient Target
```

继续保持：

```text
CodexTokenCostCore
└── Balance
    └── Relay
```

等仓库拆分稳定后再独立模块化。

---

## 1.3 Android 当前真实结构

Android 已存在独立 Relay Client：

```text
android/lib/services/relay_client.dart
android/lib/services/relay_crypto.dart
android/lib/models/relay_models.dart
android/lib/services/relay_identity_store.dart
```

当前 Android：

- HTTP App side；
- AES-256-GCM；
- Android Keystore / secure storage；
- Pairing QR；
- Production HTTPS 校验。

本轮重点不是重构 Android，而是：

1. 隐藏 Production Relay Endpoint；
2. 删除 Release 用户可配置服务器地址能力；
3. 调整 Pairing payload；
4. 增加 Release/Debug 环境隔离；
5. 清理日志与 UI 中的 Endpoint；
6. Android 首次提交前排除 keystore/local files。

---

## 1.4 Node Relay 当前真实结构

Private Relay 首版保持当前结构：

```text
src/
├── app.js
├── database.js
├── relay-hub.js
├── security.js
├── rate-limit.js
├── config.js
└── index.js

public/
test/
Dockerfile
docker-compose.yml
package.json
```

本轮不为了“架构漂亮”拆成：

```text
api/
websocket/
database/
security/
admin/
maintenance/
```

那属于后续代码质量优化，不属于仓库安全拆分的必要条件。

---

# 2. 最终简化架构

继续保留三个项目，但每个项目职责保持非常简单。

```text
PUBLIC
┌──────────────────────────────────────────┐
│ Token-Cost-App-OC-Codex                  │
│                                          │
│ macOS App                                │
│ Android App                              │
│ Swift Relay Client                       │
│ Android Relay Client                     │
│ Contract test snapshot / fixtures        │
│ Basic Architecture & Development Docs    │
└───────────────────┬──────────────────────┘
                    │
                    │ Protocol v1
                    ▼
PUBLIC
┌──────────────────────────────────────────┐
│ Token-Cost-Relay-Contract                │
│                                          │
│ protocol-v1.md                           │
│ JSON schemas                             │
│ error codes                              │
│ crypto / pairing rules                   │
│ cross-platform test vectors              │
└───────────────────┬──────────────────────┘
                    │
                    │ implementation
                    ▼
PRIVATE
┌──────────────────────────────────────────┐
│ Token-Cost-Relay                         │
│                                          │
│ Node Relay Server                        │
│ WebSocket Hub                            │
│ SQLite                                   │
│ Admin / Passkey                          │
│ Security / Rate Limit                    │
│ Docker / Deployment                      │
│ Detailed Architecture & Development Docs │
└──────────────────────────────────────────┘
```

---

# 3. 明确取消旧方案中的复杂项

本轮不做以下工作。

## 3.1 不立即拆 Swift Target

不新增：

```text
CodexTokenCostRelayProtocol
CodexTokenCostRelayClient
```

原因：

- 当前 Relay Coordinator 与 Core 有真实依赖；
- 拆 Target 会增加 DTO mapping 和依赖重构；
- 与“把服务端安全迁出 Public Repo”没有直接关系。

作为未来 P2 任务记录即可。

---

## 3.2 不新增 Public RelayMock

旧方案中的：

```text
RelayMock/
script/dev-relay.sh mock
```

本轮取消。

原因：

- 会新增一套近似服务端行为；
- 容易与真实 Relay 协议漂移；
- 增加 Node 代码与 CI；
- Public App build/test 并不需要真实 Relay；
- 内部开发可通过 sibling Private Relay 完成真实联调。

Public App 只保留：

```text
unit tests
crypto tests
QR tests
contract vectors
mocked HTTP tests
```

---

## 3.3 不做 Node 内部大重构

继续保留：

```text
app.js
database.js
relay-hub.js
security.js
rate-limit.js
security.test.js
```

拆分仓库成功后再评估代码质量优化。

---

## 3.4 不做 Git History Rewrite

除非发现：

```text
真实 Secret 已经进入公开历史
```

否则不执行。

---

# 4. 三项目职责

# 4.1 Public App

仓库：

```text
Token-Cost-App-OC-Codex
```

保留：

```text
macOS Swift App
Android Flutter App
Swift Relay Client
Android Relay Client
Relay protocol-compatible tests
基础文档
```

不得包含：

```text
Node Production Relay
Admin Server
Passkey Server
Production SQLite schema/migration
Production Docker deployment
Production infrastructure
Private Relay .env
Private Relay secrets
```

---

# 4.2 Public Contract

仓库：

```text
Token-Cost-Relay-Contract
```

保持轻量，不做 SDK。

推荐：

```text
Token-Cost-Relay-Contract/
├── README.md
├── protocol-v1.md
├── schemas/
│   ├── pairing.schema.json
│   ├── envelope.schema.json
│   ├── request.schema.json
│   └── response.schema.json
├── test-vectors/
├── SECURITY.md
├── CHANGELOG.md
└── VERSION
```

本轮不需要：

```text
Swift Package
npm package
Dart package
自动代码生成
复杂 OpenAPI SDK
```

三个实现只需固定 Contract 版本并运行 test vectors。

---

# 4.3 Private Relay

仓库：

```text
Token-Cost-Relay
```

保存：

```text
真实 Node Relay
Admin
Passkey
Database
Security
Rate Limit
Deployment
Docker
服务端测试
```

Private Repo 必须比 Public Repo 有更完整的内部文档。

---

# 5. Android Production Relay 地址安全更新

这是本轮必须完成的安全修正。

## 5.1 目标

Release APK 中：

```text
用户看不到 Relay Server URL
用户不能修改 Production Relay Server URL
扫码不能将客户端切换到任意 Relay Host
日志不打印完整 Relay URL
错误页面不打印完整 Relay URL
README 不写真实 Production Relay URL
Public source 不提交真实 Production Relay URL
```

注意：

> Relay Server 地址不是密码学 Secret。任何客户端最终都必须连接该地址，因此有能力分析 APK、DNS 或网络流量的人仍可能恢复该地址。本要求的目标是降低显性暴露、避免 UI 泄漏和防止恶意 QR 动态修改目标服务器，不得把它作为唯一安全控制。

---

# 5.2 Production Endpoint 不进入 Public Source

禁止：

```dart
const relayBaseUrl = 'https://real-production-host.example.com';
```

直接提交到 Public Repository。

推荐使用 Release build-time injection：

```dart
const String productionRelayBaseUrl =
    String.fromEnvironment('RELAY_BASE_URL');
```

Release workflow：

```bash
flutter build apk \
  --release \
  --dart-define=RELAY_BASE_URL="$RELAY_PRODUCTION_URL" \
  --obfuscate \
  --split-debug-info=build/symbols
```

GitHub Actions 中：

```text
RELAY_PRODUCTION_URL
```

作为受保护 Release Secret/Environment Secret 管理。

要求：

- workflow 不 `echo`；
- shell 不使用 `set -x`；
- 日志不得输出完整 URL；
- build 前检查值非空；
- PR workflow 不获得 Production Secret；
- fork workflow 不获得 Production Secret。

---

# 5.3 Release 禁止自定义 Endpoint

Release 代码：

```text
只允许 injected Production URL
```

禁止：

```text
Settings → Relay URL 输入框
Developer field
Custom server
QR provided server override
SharedPreferences override
Intent/deep-link endpoint override
```

如当前 UI 已存在 Server URL：

- Release 隐藏；
- Debug 可保留。

推荐：

```dart
if (kDebugMode) {
  // developer endpoint control
}
```

---

# 5.4 Production QR 不再包含 serverBaseURL

当前实际 Pairing payload 存在：

```text
version
serverBaseURL
deviceID
pairCode
e2eKey
expiresAtMilliseconds
```

在 Protocol v1 正式冻结前修改为：

```text
version
deviceID
pairCode
e2eKey
expiresAtMilliseconds
```

即：

```text
Production Pairing QR 不携带 serverBaseURL
```

原因：

1. Android Release 已有固定可信 Production Endpoint；
2. QR 中携带 Endpoint 会显性暴露服务器地址；
3. 更重要的是，会产生恶意 QR 将 Android 指向攻击者 Relay 的风险；
4. Server endpoint 不属于设备配对密钥材料。

---

# 5.5 Debug / Development Endpoint

开发环境使用显式本地参数：

```bash
flutter run \
  --dart-define=RELAY_BASE_URL=http://10.0.2.2:8787
```

或者：

```bash
flutter run \
  --dart-define=RELAY_BASE_URL=http://127.0.0.1:8787
```

Debug 可以允许：

```text
localhost
127.0.0.1
10.0.2.2
局域网开发地址
```

Release：

```text
HTTPS only
固定 Production Host
禁止 override
```

---

# 5.6 Android 日志脱敏

全局检查：

```text
print(...)
debugPrint(...)
logger.*
toString()
Exception(...)
```

不得输出：

```text
完整 Relay URL
pairCode
e2eKey
Bearer token
device secret
ciphertext payload（无必要时）
完整 QR payload
```

如需要调试：

```text
Relay request failed
Relay connection unavailable
Pairing failed
```

而不是：

```text
Request to https://production-host/... failed
```

---

# 5.7 APK 基础加固

Release 构建建议：

```text
Flutter AOT Release
--obfuscate
--split-debug-info
R8 / minify（若当前配置兼容）
resource shrinking（若兼容）
```

不要实现自制 XOR/字符串“加密”来假装 URL 无法恢复。

---

# 6. Protocol v1 简化设计

Public Contract 只描述当前真实协议。

本轮 v1：

## Pairing URI

```text
balance-relay://pair?data=<base64url JSON>
```

Production payload：

```json
{
  "version": 1,
  "deviceID": "...",
  "pairCode": "...",
  "e2eKey": "...",
  "expiresAtMilliseconds": 0
}
```

不包含：

```text
serverBaseURL
```

---

## Envelope

保持当前：

```json
{
  "v": 1,
  "nonce": "...",
  "ciphertext": "...",
  "tag": "..."
}
```

不为了符合旧规划新增无必要字段。

---

## HTTP

以当前真实端点为准，冻结前由 OpenCode 扫描服务端路由生成最终表。

至少检查：

```text
/api/v1/devices/register
/api/v1/pair/start
/api/v1/pair/claim
/api/v1/devices/revoke
/api/v1/devices
/api/v1/device/registration-status
/api/v1/device/status
/api/v1/device/pairing-status
/api/v1/relay/query
```

---

## WebSocket

至少：

```text
/ws/pc
relay.request
relay.response
```

---

## Error Code

客户端不再依赖自由文本。

服务端：

```json
{
  "code": "PC_OFFLINE",
  "error": "PC offline"
}
```

客户端：

```text
code → 程序逻辑
error → UI 展示 / 兼容
```

---

# 7. Private Relay 文档要求

Private Repo 必须详细。

至少：

```text
README.md
ARCHITECTURE.md
DEVELOPMENT.md
SECURITY.md
DEPLOYMENT.md
CHANGELOG.md
```

---

## 7.1 Private README.md

必须包含：

```text
项目用途
Repository Boundary
快速启动
环境变量说明
测试命令
数据库位置
Admin 入口说明
开发/测试/生产环境区分
Protocol Contract version
相关文档索引
```

不得包含真实 Secret。

---

## 7.2 Private ARCHITECTURE.md

必须详细描述：

```text
整体架构
HTTP request flow
WebSocket flow
Pairing flow
E2EE flow
Device lifecycle
SQLite tables / relationships
Replay protection
Rate limiting
Admin / Passkey
Session
Logging
Maintenance
Trust boundaries
Failure handling
```

推荐附 Mermaid。

---

## 7.3 Private DEVELOPMENT.md

必须包含：

```text
环境要求
npm install
本地启动
环境变量
测试数据库
如何运行 npm test
如何连接 Public macOS Client
如何连接 Public Android Client
如何使用 sibling repositories
Debug endpoint 配置
如何更新 Contract
兼容性规则
常见错误
```

---

## 7.4 Private SECURITY.md

至少：

```text
Threat Model
Credential Boundary
Encryption
Pairing
Replay
Authentication
Authorization
Rate Limit
WebSocket
Admin Passkey
Secret handling
Logging policy
Security test
Vulnerability reporting
```

---

## 7.5 Private DEPLOYMENT.md

至少：

```text
Staging
Production
Docker
Environment variables
Database volume
Reverse proxy
HTTPS/WSS
Trusted proxy
Backup
Rollback
Health check
Update procedure
Secret rotation
```

---

# 8. Public App 文档要求

Public Repo 文档只保留用户和外部开发者真正需要的信息。

不要把 Private 实现细节复制进 Public。

必须更新：

```text
README.md
SECURITY.md
CHANGELOG.md
docs/架构逻辑链图.md
docs/开发手册.md
docs/功能模块关联清单.md
```

如果已有同类内容：

```text
直接更新现有文档
不要重复新建多个同义文档
```

---

## 8.1 Public README.md

至少说明：

```text
Token Cost App 是什么
macOS / Android
Relay 是可选跨端功能
Production Relay Server 不在 Public Repo
客户端与 Relay 使用 E2EE envelope
Provider credential 不进入 Relay
如何 build macOS
如何 build Android
如何进行本地 Relay client 开发
Contract Repo 位置
```

不要出现：

```text
真实 Production Relay URL
Private deployment command
Private database structure
Private Admin internals
```

---

## 8.2 Public 架构说明

保持基本层级：

```text
Token-Cost-App-OC-Codex
├── macOS App
│   └── Balance/Relay Client
│
├── Android App
│   └── Relay Client
│
└── Protocol v1
        │
        ▼
   Private Relay
```

不再展示不存在的：

```text
CodexTokenCostRelayProtocol target
CodexTokenCostRelayClient target
RelayMock
```

---

## 8.3 Public 开发说明

只包含：

```text
Swift build/test
Flutter analyze/test/build
Debug Relay endpoint 配置
Contract test vectors
如何与 sibling Private Relay 联调（仅描述目录关系，不暴露 Private URL）
```

示例：

```text
workspace/
├── Token-Cost-App-OC-Codex/
├── Token-Cost-Relay/
└── Token-Cost-Relay-Contract/
```

不要写真实用户路径。

---

# 9. Public Contract 文档要求

至少：

```text
README.md
protocol-v1.md
SECURITY.md
CHANGELOG.md
VERSION
```

README：

```text
协议作用
当前版本
兼容原则
三端关系
如何运行 test vectors
```

Protocol 文档只写：

```text
数据结构
字段
API
WS
Error Code
Crypto Envelope
Pairing
```

不得写：

```text
Production hostname
Admin hostname
database password
deployment topology
真实 infra 信息
```

---

# 10. 全量脚本 / 文件关联 / 指向审计

这是本轮强制验收项。

拆分完成后，OpenCode 必须做一次 repository-wide reference audit。

---

## 10.1 Public App 检查范围

检查：

```text
Package.swift
Sources/**
Tests/**
android/**
README.md
SECURITY.md
CHANGELOG.md
docs/**
script/**
.github/**
.gitignore
.gitattributes
release/**
Resources/**
```

搜索：

```bash
rg -n --hidden \
  --glob '!**/.git/**' \
  'relay/|Token-Cost-Relay|Token-Cost-Relay-Contract|serverBaseURL|RELAY_|relayBaseUrl|relayBaseURL'
```

逐条分类：

```text
有效
需要改路径
需要改描述
需要删除
Private 信息泄漏
```

---

## 10.2 Private Relay 检查范围

检查：

```text
src/**
test/**
public/**
README.md
ARCHITECTURE.md
DEVELOPMENT.md
SECURITY.md
DEPLOYMENT.md
Dockerfile
docker-compose.yml
package.json
.github/**
.gitignore
.env.example
```

搜索 Public App 的旧本地路径与旧相对路径。

---

## 10.3 Contract 检查范围

检查：

```text
README.md
protocol-v1.md
schemas/**
test-vectors/**
SECURITY.md
CHANGELOG.md
VERSION
.github/**
```

确认：

```text
Schema 与三端实际模型一致
字段名称一致
版本一致
Error Code 一致
QR 字段一致
serverBaseURL 已从 Production Pairing 移除
```

---

# 11. 跨项目引用完整性

拆分后必须验证以下所有关联。

## Public → Contract

只能通过：

```text
文档链接
版本号
test vector snapshot
```

不得构建时联网拉取 Private Repo。

---

## Private → Contract

允许：

```text
CI checkout Contract
本地 sibling Contract
固定 tag/version
```

---

## Internal Development

推荐：

```text
workspace/
├── Token-Cost-App-OC-Codex/
├── Token-Cost-Relay/
└── Token-Cost-Relay-Contract/
```

不使用：

```text
git submodule
git subtree
Public → Private source dependency
```

---

# 12. CI 调整

# 12.1 Public App CI

保持简单：

```text
Swift build
Swift test
Flutter analyze
Flutter test
Contract fixtures test
Secret scan
Personal-info scan
Broken-reference scan
```

不启动 Production Relay。

---

# 12.2 Contract CI

最小：

```text
JSON validation
schema validation
test-vector validity
version consistency
broken-link check
```

---

# 12.3 Private Relay CI

至少：

```text
npm test
Secret scan
dependency audit
Contract compatibility
lint（若已有）
```

真实三端 Staging E2E 暂时可以人工执行。

不要求本轮搭建复杂自动 E2E Harness。

---

# 13. Android CI / Release

Android 首次进入 Public Git 前必须排除：

```text
android/android/app/keystore/*.jks
android/android/key.properties
android/android/local.properties
*.keystore
*.jks
```

确认 `.gitignore`。

Release Workflow：

```text
Production endpoint 从 GitHub Release Secret 注入
签名材料从 GitHub Secret 注入
不向 PR 暴露
不打印
不提交生成文件
```

Build 完成后：

```text
保留 split-debug-info 到安全位置
Release artifact 不附带 debug symbol
```

---

# 14. 个人信息清理

目标：

> 三个项目中只保留项目运行、授权、贡献和 GitHub 所必需的信息；删除与功能无关的个人身份和开发机信息。

---

## 14.1 必查内容

搜索：

```bash
rg -n --hidden \
  --glob '!**/.git/**' \
  '/Users/|C:\\Users\\|11169285|@gmail\.com|@qq\.com|@163\.com|author|created by|copyright'
```

再搜索已知：

```text
个人姓名
个人英文名
个人邮箱
手机号
工号
本机用户名
本地绝对路径
个人 Git remote
个人目录名称
IDE workspace username
```

---

## 14.2 路径处理

禁止：

```text
/Users/<user>/Documents/...
/Users/<real-name>/...
C:\Users\<real-name>\...
```

替换：

```text
$REPO_ROOT
<repo-root>
~/Developer/project
workspace/
```

---

## 14.3 文档作者信息

如果文档中的：

```text
Author:
Created by:
Maintainer:
Email:
```

不是项目运行/许可证必须信息，则删除或改为：

```text
Project Maintainers
```

GitHub 联系方式优先使用：

```text
Issues
Security Advisory
```

而不是个人邮箱。

---

## 14.4 Git Commit 身份

未来提交建议配置：

```text
GitHub noreply email
```

例如：

```bash
git config user.useConfigOnly true
```

实际 name/email 由用户配置，不在脚本里硬编码。

不因为普通 commit author 信息执行 Git history rewrite。

只有真实敏感个人信息进入文件内容时才单独处理。

---

## 14.5 IDE / Agent / Cache

检查：

```text
.DS_Store
xcuserdata/
.idea/
.vscode/
.codex/
.sisyphus/
.playwright-mcp/
.build/
dart_tool/
build/
node_modules/
```

原则：

- 运行必要配置可保留；
- 含个人路径、session、cache、history 的删除并 gitignore；
- 不提交 AI 工具本地会话信息；
- 不提交浏览器/profile 路径。

---

# 15. Secret Scan

三项目分别扫描。

重点：

```text
.env
.env.*
key.properties
local.properties
*.jks
*.keystore
*.p12
*.mobileprovision
API key
Bearer token
Passkey secret
JWT secret
database password
SSH key
cloud token
```

`.env.example` 只允许：

```text
变量名称
安全占位值
```

不允许真实值。

---

# 16. Git / GitHub 实际操作顺序

采用最小风险顺序。

# Phase 0 — 基线

```bash
git status
git branch --show-current
git remote -v
git ls-files relay/
git log --all -- relay/
git ls-files android/
git log --all -- android/
```

输出基线报告。

然后：

```text
Secret Scan
Personal Information Scan
Reference Scan
```

---

# Phase 1 — 创建 Private Relay

创建：

```text
Token-Cost-Relay
Visibility: Private
```

采用 clean copy：

```text
local relay/
    ↓
new private repository
```

不要保留不存在的历史。

提交前排除：

```text
.env
node_modules/
data/
database files
logs
cache
production secrets
```

首次提交后：

```bash
npm install
npm test
```

新增：

```text
README.md
ARCHITECTURE.md
DEVELOPMENT.md
SECURITY.md
DEPLOYMENT.md
CHANGELOG.md
```

---

# Phase 2 — Relay Endpoint / Protocol 安全修正

在冻结 Protocol v1 前完成：

```text
删除 Production Pairing 中 serverBaseURL
Android Release 固定 endpoint
Android Release 无 endpoint UI
Android Release 禁止 custom endpoint
Production endpoint build-time injection
日志脱敏
Error Code 结构化
```

同步修改：

```text
macOS QR generator
Android QR parser
Node pair logic（如依赖）
tests
Contract
```

---

# Phase 3 — 创建 Public Contract

创建：

```text
Token-Cost-Relay-Contract
Visibility: Public
```

只提交：

```text
README
protocol-v1
schemas
test-vectors
SECURITY
CHANGELOG
VERSION
```

冻结：

```text
v1.0.0
```

前必须保证：

```text
Swift PASS
Dart PASS
Node PASS
```

---

# Phase 4 — Public App 首次提交 Android

Public App 只加入：

```text
android/
Swift Relay client changes
Contract fixtures
docs updates
CI updates
```

绝对不加入：

```text
relay/
```

提交前：

```bash
git status --short
git diff --cached --name-only
```

人工确认没有：

```text
relay/src
relay/public
relay/test
.env
jks
key.properties
local.properties
```

---

# Phase 5 — 全量引用与文档更新

更新三个项目所有 README。

Public App：

```text
README.md
SECURITY.md
CHANGELOG.md
docs/架构逻辑链图.md
docs/开发手册.md
docs/功能模块关联清单.md
其他包含 Relay/Android 的 docs
```

Contract：

```text
README.md
protocol-v1.md
SECURITY.md
CHANGELOG.md
```

Private：

```text
README.md
ARCHITECTURE.md
DEVELOPMENT.md
SECURITY.md
DEPLOYMENT.md
CHANGELOG.md
```

然后运行全局 `rg` 检查。

---

# Phase 6 — Staging 联调

目录：

```text
workspace/
├── Token-Cost-App-OC-Codex/
├── Token-Cost-Relay/
└── Token-Cost-Relay-Contract/
```

执行：

```text
Mac register
QR generate
Android scan
pair claim
WS connect
balance request
response decrypt
reconnect
timeout
revoke
delete device
```

特别验证：

```text
QR 不包含 Production URL
Android UI 不显示 Production URL
Android log 不显示 Production URL
Android Release 不接受 QR custom URL
Android Release 不接受 runtime custom endpoint
```

---

# 17. 全局安全检查

至少检查：

## Relay

```text
Authentication
Pairing expiration
One-time claim
Replay protection
WebSocket auth
Device revoke
Rate limit
XFF
Passkey challenge
Admin session
Logging
```

## Client

```text
AES-GCM tag validation
nonce validation
requestId matching
expiry
replay
HTTPS Release enforcement
endpoint trust
secure storage
```

---

# 18. Balance/Sync 边界

调研发现：

```text
Sources/CodexTokenCostCore/Balance/Sync/
```

属于另外一个 Credential Sync 系统。

本轮：

```text
不迁入 Private Relay
不写入 Relay Contract
不与 Relay 的 E2EE 说明混合
```

所有文档必须区分：

```text
Relay
≠
Credential Sync
```

如果 Public 文档写：

```text
Provider credentials never leave Mac
```

必须重新核对 Sync 功能实际行为。

准确表述应按真实产品行为调整，避免与 Sync 功能冲突。

---

# 19. README / Docs 一致性规则

所有文档统一以下术语：

```text
Public App
Public Relay Contract
Private Relay
Protocol v1
Production Relay
Development Relay
```

不要混用：

```text
server
backend
cloud relay
relay service
middle server
```

除非明确解释。

所有架构图必须与代码现状一致。

禁止文档出现：

```text
不存在的 RelayMock
不存在的 Swift Relay Targets
已删除的 relay/ public path
旧 serverBaseURL pairing field
真实 Production URL
个人绝对路径
```

---

# 20. 最终脚本检查

逐个检查：

```text
script/**
.github/workflows/**
Package.swift
android/**/build.gradle*
android/pubspec.yaml
android/README.md
relay/package.json
relay/Dockerfile
relay/docker-compose.yml
```

确认：

```text
路径有效
working-directory 有效
文件存在
脚本执行目录正确
relative path 正确
CI artifact path 正确
release path 正确
README command 可执行
```

对于每一个 shell script：

```bash
bash -n <script>
```

如适用。

对于 workflow：

```text
检查 referenced path
检查 secret name
检查 working-directory
检查 artifact path
检查 permissions
```

---

# 21. 最终验收标准

必须全部满足。

## Repository Boundary

- [ ] Public App 无 `relay/src`
- [ ] Public App 无 Relay Admin Server
- [ ] Public App 无 Production Docker config
- [ ] Private Relay visibility = Private
- [ ] Contract visibility = Public
- [ ] Public build/test 不需要 Private Repo

## Android Endpoint

- [ ] Production URL 不提交到 Public source
- [ ] Release APK UI 不显示 URL
- [ ] Release Settings 无 custom Relay URL
- [ ] Production QR 不包含 `serverBaseURL`
- [ ] Release 不接受 QR endpoint override
- [ ] Debug 可显式设置开发 Endpoint
- [ ] Release HTTPS only
- [ ] Production URL 不写日志

## Protocol

- [ ] Contract v1 与 Swift 一致
- [ ] Contract v1 与 Dart 一致
- [ ] Contract v1 与 Node 一致
- [ ] Test vectors PASS
- [ ] Error code 不依赖自由文本

## Tests

```text
swift build        PASS
swift test         PASS
flutter analyze    PASS
flutter test       PASS
npm test           PASS
contract vectors   PASS
staging E2E        PASS
```

## Security

- [ ] Secret Scan PASS
- [ ] Credential 未进入 Relay
- [ ] E2EE Key 未进入 Relay
- [ ] Replay tests PASS
- [ ] Pairing expiry PASS
- [ ] Revoke PASS
- [ ] Admin Passkey manual test PASS
- [ ] Logs sanitized

## References

- [ ] README paths valid
- [ ] docs paths valid
- [ ] script paths valid
- [ ] workflow paths valid
- [ ] test fixture paths valid
- [ ] release paths valid
- [ ] no obsolete `relay/` public references

## Personal Information

- [ ] 无真实 `/Users/<username>/...`
- [ ] 无工号
- [ ] 无私人邮箱
- [ ] 无手机号
- [ ] 无本地 keystore path
- [ ] 无 IDE user data
- [ ] 无 AI Agent local session data
- [ ] 无不必要 author metadata

## Documentation

Public App：

- [ ] README updated
- [ ] SECURITY updated
- [ ] CHANGELOG updated
- [ ] 架构逻辑链图 updated
- [ ] 开发手册 updated
- [ ] 功能模块关联清单 updated

Contract：

- [ ] README updated
- [ ] protocol-v1 finalized
- [ ] SECURITY updated
- [ ] CHANGELOG updated
- [ ] VERSION finalized

Private Relay：

- [ ] README complete
- [ ] ARCHITECTURE detailed
- [ ] DEVELOPMENT detailed
- [ ] SECURITY detailed
- [ ] DEPLOYMENT detailed
- [ ] CHANGELOG updated

---

# 22. 本轮明确不做

以下全部作为后续优化，不阻塞本轮：

```text
Swift Relay Target 拆分
Relay DTO 全面解耦
Node app.js 拆 routes
database.js 拆 DAO
security.test.js 拆多个文件
Public RelayMock
复杂自动三端 E2E Harness
Git history rewrite
Submodule
Subtree
SDK 自动生成
```

---

# 23. 后续 P2 优化

仓库拆分稳定后再评估：

1. `CodexTokenCostRelayProtocol`
2. `CodexTokenCostRelayClient`
3. DTO 与 `BalanceSnapshot` 解耦
4. Node route 拆分
5. Database layer 拆分
6. Security test 拆分
7. Private automatic E2E
8. Public development mock server

所有 P2 任务独立 PR，不与本次安全拆分混合。

---

# 24. OpenCode 最终输出要求

完成后输出：

# A. Repository Result

```text
Public App:
...

Public Contract:
...

Private Relay:
...
```

# B. Security Changes

重点说明：

```text
Android Production Endpoint
QR serverBaseURL removal
Release endpoint lock
Log sanitization
Pairing
Replay
Error Code
Secret handling
```

# C. Files Changed

按三个仓库分别列。

# D. GitHub Operations

列出：

```text
repo created
visibility
branch
commit
PR
tag
release
secret/environment configuration
```

不要输出 Secret 内容。

# E. Test Result

必须是实际执行结果：

```text
swift build:
swift test:
flutter analyze:
flutter test:
npm test:
contract:
staging E2E:
```

# F. Reference Audit

输出：

```text
Broken reference: 0
Obsolete relay path: 0
Absolute personal path: 0
```

如果不是 0，列出剩余项。

# G. Personal Information Audit

列出：

```text
Removed:
...

Retained:
...
Reason:
...
```

不得在报告里重新打印敏感内容。

# H. Documentation Result

列出所有 README / docs 更新。

# I. Remaining Risks

必须明确：

1. Relay 地址即使不显性显示，仍可能通过 APK 逆向、DNS 或网络流量被识别；
2. Private Repo 不是密码学安全边界；
3. `Balance/Sync` 是独立安全域；
4. 如果 canonical Git history 与调研 worktree 不同，需要单独处理历史问题。

---

# 25. 最终架构

```text
                     PUBLIC

        Token-Cost-App-OC-Codex
        ┌──────────────────────────┐
        │ macOS App                │
        │ Android App              │
        │ Relay Clients            │
        │ Basic Docs               │
        └────────────┬─────────────┘
                     │
                     │ Protocol v1
                     ▼
        Token-Cost-Relay-Contract
        ┌──────────────────────────┐
        │ Protocol                 │
        │ Schemas                  │
        │ Error Codes              │
        │ Test Vectors             │
        └────────────┬─────────────┘
                     │

                    PRIVATE

                     ▼
        Token-Cost-Relay
        ┌──────────────────────────┐
        │ Node Relay               │
        │ WS Hub                   │
        │ Database                 │
        │ Security / Rate Limit    │
        │ Admin / Passkey          │
        │ Deployment               │
        │ Detailed Internal Docs   │
        └──────────────────────────┘
```

本轮不增加更多中间层。

---

# 26. 最终原则

本次拆分的目标不是把现有项目改造成复杂的多仓库平台，而是建立三个清晰边界：

```text
Public App
    = 产品客户端

Public Contract
    = 三端共同语言

Private Relay
    = 服务端实现与部署
```

安全上：

```text
Endpoint 不显性暴露
≠
Endpoint 是 Secret

Private Source
≠
系统安全
```

真正的安全基础仍然是：

```text
E2EE
Authentication
Pairing security
Replay protection
Endpoint trust
Secure storage
Rate limiting
Passkey security
Secret management
Secure deployment
Testing
```

执行结束时，必须同时完成：

```text
代码
GitHub
CI
脚本检查
引用检查
个人信息清理
README
架构说明
开发说明
安全说明
部署说明
最终使用说明
```

不得只完成代码迁移。
