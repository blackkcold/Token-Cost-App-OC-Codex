# OpenCode Skills 管理器 — v0.7.0 完整执行方案（八次修订版·终版审核·R8 Final Audit）

> 目标版本：`v0.7.0 / Unreleased`
> 范围：只做 OpenCode Skills 管理，不做 MCP，不写 provider / agent / plugin / mcp
> 状态：**R8 终版审核通过**，在 R7 基础上补入官方 docs 全量交叉核查 + 本地 4-agent 并联审计 + 7 项新发现修正；**code-fit 确认：当前 3-tab + 5-StateObject 结构适配增量添加，不属于"大改"，不触发 Section 15 降级**。
> 安全等级：受限写入——仅在 OpenCode 已安装、目标配置文件已存在且通过校验时，才允许修改有效配置目标中的 `permission.skill` 相关子树；未安装时不自动创建 `opencode.json`，只提示安装。
> 修订轮次：Round 8（Final Audit），核查证据：R1-R7 全部证据链 + **R8 新增**：OpenCode 官方 docs（config/permissions/skills + config.json schema）全量交叉核查 × 本地 opencode.json/h-my-openagent.json/源码结构/skill 目录 4-agent 并联审计 + 7 项新发现（config 热加载行为/OPENCODE_CONFIG 环境变量盲区/旧 .bak 清理/scout agent 补全/globalConfigFile 加载顺序/mxm-cli symlink 事实修正/测试行数修正）+ 双 TOCTOU 窗口加固 + 现有 .bak 清理方案 + Phase 0.5 真实文件扫描验证

---

## SDD Delta Card

| 项 | 内容 |
|---|---|
| Mode | `audit + feature-planning` (Round 6 Simplified) |
| Goal | 在不引入大结构调整前提下，收敛为安全但简便的 MVP：OpenCode 安装门控、官方优先级检测、自定义配置目录、permission 树状归类与状态区分；若当前项目结构不适配，则停在只读版 |
| Evidence checked | **R4**: 官方 docs + 源码 + 本地代码审计 + 用户 actual config；**R5**: `oh-my-openagent.json`（227 行，11 自定义 agent + 8 category，无 permission.skill 冲突）、`script/build_and_run_codex.sh:145` 确认 `--disable-sandbox`（无 App Sandbox）、oracle 验证 Darwin `open()+O_EXCL` 完全可行；**R6**: 当前项目最新代码结构适配复核；**R7**: opencode.json 直接审计（493 行，`permission.skill`=string `"allow"` 第 43 行）+ 安全边界 TOCTOU/symlink/JSONC/backup 4 项深度验证 + 项目 code-fit 确认；**R8 新增**: OpenCode 官方 docs（config/permissions/skills）+ config.json Schema 全量交叉核查 × 4-agent 并联本地审计（代码结构/opencode配置/skill目录/安全边界）+ mmx-cli 部署方式修正（symlink 非独立副本）+ 测试文件行数修正（1019 非 974）+ scout agent 补全 + 跨卷原子性确认 |
| Current stage | before-code — **R8 终版审核完成，code-fit 通过，可进入 Phase 0.5 原型验证** |
| Allowed files | 方案文档、`Sources/CodexTokenCostCore/`（优先复用现有结构，必要时再细分 OpenCode/）、App Stores/Views 接入、本地化、测试、README/SECURITY/CHANGELOG/docs |
| Forbidden files | `Package.swift`、MCP 相关、provider 配置、真实用户 secrets、Keychain、系统目录 |
| Minimal plan | 方案修订 → 按 Core → App → 接入 → 测试 → 文档 → 验收实施 |
| Verification | `swift test`、`swift build -c release`、手动 JSON patch 验证、diff 安全检查 |
| Safety boundary | 不全盘遍历，不输出完整 config，不渲染 secrets，不写 JSONC，不自动创建配置文件，不写项目级/managed/custom config，不在未安装 OpenCode 时进入写回 |

---

## 1. 交叉核查结论

### 1.1 交叉核查发现（合并 R1 + R2 + R3 + R4 + R5 + R7）

| 严重级别 | 问题 | 修正 |
|---|---|---|
| **High** | wildcard 只设计 `*` prefix/suffix/full | 已设计 `*`+ `?` + last-match-wins，源码确认 `Wildcard.match()` 一致 |
| **High** | 规则顺序依赖普通 JSON 字典 | 从 raw text 用 scanner 抽取 ordered members，`JSONSerialization` 仅用于合法性 guard |
| **High** | 只扫描 `~/.config/opencode/skills` | 扩展到 `.claude/.agents` + singular `skill/` 目录 |
| **High** | agent native defaults 改变 effective 结果 | 展示 agent native defaults matrix（**8 列：Build/Plan/General/Explore/Scout/Compaction/Title/Summary**；**R8 扩展**：官方 Schema 含 scout 内置 agent，默认 `"*": "deny"`） |
| **High** | 写回事务缺少并发保护 | hash guard + batch transaction + `.bak-YYYYMMDD-HHmmss-<uuid8>` 防碰撞 |
| **High** | string `"skill": "allow"` → nested object 的 text patch 极度脆弱 | Phase 0.5 独立原型验证步骤（12 个场景）；若失败自动激活 Section 15 Fallback Plan |
| **High** | 新建 `opencode.json` 会丢失 `$schema` 和默认值 | 文件不存在时拒绝写入，提示用户先启动 OpenCode |
| **High** | README.md 安全声明与写入功能直接矛盾 | R4 已同步修改 README/SECURITY/CHANGELOG，标注 Product Security Posture Change |
| **High** | Permission 默认值展示 — UI 中 "Implicit Default" 应为 "allow (default)" | 与官方 docs "allows all operations" 一致 |
| **High** | **配置加载/写入对 `config.json`、`opencode.json`、`opencode.jsonc` 的真实行为存在版本差异，不能硬编码** | 以本机已安装 OpenCode 的实际版本为准，先做文件存在性/加载顺序探测；官方 precedence、源码与用户自定义配置目录交叉核对后，再决定只读展示与写入目标 |
| **High** | **OpenCode 未安装时误创建配置或误进入写入流程** | 安装门控：未安装只显示安装提示，不自动创建 `opencode.json` |
| **High** | **方案依赖旧代码假设，可能与当前项目接入点不兼容** | 先做 code-fit 复核，按当前仓库现有 Settings/Stores/Views/Paths 选择最小 patch；若需大改结构则停在只读版 |
| **High** | **R4: Phase 0.5 原型失败无 fallback** | Section 15 Fallback Plan：仅支持 object 形态 `permission.skill` |
| **High** | **R4: SafeFileStore 架构与 `~/.config/opencode/` 写入不兼容** | 新建独立 `OpenCodeConfigFileStore`，不复用 SafeFileStore，复用安全思想 |
| **High** | **R4: `.json` 文件内含非标准 `//` 注释漏检** | raw text 注释扫描，标记只读 |
| **High** | **R4: `$schema` 版本兼容性未检测** | Phase 2 新增版本检测，未知版本禁用写入 |
| **High** | **R4: hash guard 失败信息不足** | 展示 redacted diff + "仍然写入"选项 |
| **High** | **R5: App Sandbox 兼容性未验证** | ✅ **已解决** — `build_and_run_codex.sh:145` 使用 `--disable-sandbox`，codesign 无 entitlements，App 无沙箱限制，可自由写入 `~/.config/` |
| **High** | **R5: O_EXCL 具体实现未验证** | ✅ **已解决** — oracle 确认 Darwin `open(path, O_WRONLY\|O_CREAT\|O_EXCL\|O_CLOEXEC, 0o600)` 完全可行，内核级原子保证，EEXIST(errno=17) 换 UUID 重试 |
| **High** | **R5: oh-my-openagent.json 未审计** | ✅ **已解决** — 227 行，11 自定义 agent，无 `permission.skill` 字段，不影响全局 skill 权限管理。Agent 的 `skills` 数组为白名单，独立于 permission，UI 中标注即可 |
| **High** | **R7: Phase 0.5 标记为"可选"但实际不可跳过** | **已修正** — 当前用户 `permission.skill` 是 string `"allow"`（第 43 行），若跳过 text patch 原型则 Section 15 Fallback 只支持 object 形态，意味着 100% 用户（string 形态）落入只读模式。Phase 0.5 已更正为 `REQUIRED (CRITICAL PATH)` |
| **High** | **R7: TOCTOU 竞态窗口** | **已识别，增加轻量防护** — hash guard（Step 14）与 O_EXCL 写入（Step 16）之间存在时间窗口，O_EXCL 仅保护 `.tmp` 文件，不保护原始文件。措施：Step 14 增加 inode+mtime 比对；用户确认弹窗明确标注"外部并发修改风险" |
| **High** | **R7: JSONC 注释检测存在误判风险** | **已识别，改进检测逻辑** — `.json` 文件中 `//`/`/* */` 可能在合法字符串值中出现（如 URL、帮助文本），不可仅用字符串匹配判定为 JSONC。措施：text scanner 需区分字符串内外上下文；仅对字符串外的 `//`/`/* */` 序列触发只读标记 |
| **High** | **R7: Symlink 攻击向量未覆盖** | **已识别，增加 symlink 解析验证** — 技能发现阶段需对每个发现的 skill 目录做 `resolvingSymlinksInPath()` 并验证目标路径仍在三大允许目录树内；拒绝指向允许树外的 symlink |
| **High** | **R7: 文档状态与计划 Phase 0 不同步** | **已识别，Phase 0 更新为"确认并补充"** — CHANGELOG/README/SECURITY 已包含 v0.7.0 Skills 描述，Phase 0.3-0.5 改为确认当前内容完整性 + 按需补充缺失项 |
| **High** | **R8: OpenCode 配置不支持热加载** | **已识别（R8 跨官方 docs 交叉核查）** — 官方 docs 零提及 config hot-reload；`watcher` 仅用于项目文件监听；源码 `config.ts` 使用 Effect.ts `state()` 一次性初始化。措施：UI 确认弹窗增加红色警告"⚠️ 权限变更将在 OpenCode 重启后生效"；Skills 页面底部增加持久状态条 "OpenCode 运行中 — 请重启以应用变更" |
| **High** | **R8: OPENCODE_CONFIG 环境变量对 GUI App 不可见** | **已识别（R8 交叉核查）** — 官方 confirm `OPENCODE_CONFIG` 为第 3 优先级配置层；但 GUI App 的 `ProcessInfo.environment` 不包含 shell profile 中 `export` 的变量。措施：Phase 1 增加 shell profile scanner（`.zshrc`/`.bash_profile`/`.zprofile`）检测 `OPENCODE_CONFIG` export；UI 增加手动输入框覆盖 |
| **High** | **R8: 现有 37 个历史 .bak 文件含明文 secrets** | **已识别（R8 本地审计）** — `~/.config/opencode/` 下有 37 个历史 .bak 文件（opencode.json×28 + oh-my-openagent.json×7 + AGENTS.md×2），全部含明文 MCP secrets。措施：Phase 0 增加 Step 0.4 清理步骤，保留最新 3 个，其余 `FileManager.removeItem` 删除 |
| **High** | **R8: 内置 agent scout 遗漏** | **已识别（R8 Schema 审计）** — 官方 Schema `Config.properties.agent.properties` 列有 scout agent（默认权限 `"*": "deny"`）。Agent matrix 从 7 列扩展为 **8 列**（Build/Plan/General/Explore/**Scout**/Compaction/Title/Summary） |
| **High** | **R8: 写回流水线存在第二个 TOCTOU 窗口** | **已识别（R8 Oracle 审计）** — Step 15（备份）至 Step 19（replaceItemAt）之间，OpenCode 可能修改原始文件，replaceItemAt 原子覆盖导致丢失修改。措施：Step 18→19 之间增加第三次 inode+mtime 快速检查；不一致则中止并提示重新加载 |
| **High** | **R8: mmx-cli 部署方式核查错误** | **已修正** — R7 声称"两个独立副本，非 symlink"；R8 实测 `ls -la` 确认 `~/.claude/skills/mmx-cli → ../../.agents/skills/mmx-cli` 为 **symlink**。去重策略不受影响，标注改为 "symlink duplicate" |
| **High** | **R8: 测试文件行数过时** | **已修正** — 文档声称 974 行，实际 `CodexTokenCostCoreTests.swift` 为 **1019 行**（+45 行，推测 R7 审核后新增了 BrowserCookieExtractor/PBKDF2/BillingOverrides 等测试） |
| Medium | **R7: 备份文件 Secret 残留** | **已识别，增加备份 redaction** — `.bak-YYYYMMDD-HHmmss-<uuid8>` 是完整副本含 MCP secrets。措施：备份不存放于 `~/.config/opencode/` 同目录，改为 `~/Library/Application Support/CodexTokenCost/backups/` 沙箱内；备份 rotate 时安全删除（`shred` 覆写后 unlink） |
| Medium | **R7: O_EXCL tmp 文件残留未定义清理路径** | **已识别，rollback 增加 tmp 清理** — 若 `replaceItemAt` 失败，`.tmp.<uuid>` 残留。措施：Step 21 rollback 中增加 tmp 文件检查与清理 |
| Medium | **R7: 写回中断恢复未定义** | **已识别，增加启动时残留检测** — App 崩溃可能残留 `.tmp.<uuid>` 或备份比 target 更新。措施：`OpenCodeConfigFileStore.init()` 增加启动时残留检测与清理逻辑 |
| Medium | **R7: 自定义配置目录安全路径校验缺失** | **已识别，增加安全校验规则** — 用户输入的自定义目录需：(a) 在 `$HOME` 内，(b) `resolvingSymlinksInPath()` 解析后仍在其内，(c) 拒绝网络/ AFP / SMB 挂载路径 |
| Medium | **R7: `O_CLOEXEC` 标志无实际安全收益** | **已识别，移除** — `O_CLOEXEC` 防止 fork/exec 后 fd 泄露，Swift macOS App 不使用 fork/exec，该标志无安全价值。从 `open()` flags 中移除 |
| Medium | **R7: `replaceItemAt` 不保留 inode** | **已识别，但不影响功能** — `FileManager.replaceItemAt` 创建新文件 + 替换，不保留 inode。对 config 场景无功能影响，在 SECURITY.md 中记录此行为 |
| Medium | **R7: 文本补丁后结构等价性验证缺失** | **已识别，增加 diff guard 增强** — Step 18 的 diff guard 仅确认 `permission.skill` 子树变化，未验证其他 key 未被意外修改。措施：增加"原始 JSON ↔ 输出 JSON 除 `permission.skill` 外结构等价"断言 |
| Medium | **R7: mmx-cli symlink 核查修正（R8 二次确认）** | R5 标注为 symlink，R7 误判为独立副本，R8 最终确认：`~/.claude/skills/mmx-cli → ../../.agents/skills/mmx-cli` 是 symlink。canonical URL 去重有效，discovery log 标注 "symlink duplicate" |
| Medium | manifest 校验过于绝对 | 分级：Error/Warning/Info，description 缺失为 Warning |
| Medium | duplicate 语义 — 后加载覆盖，方案"禁用写入"正确 | 官方源码遇 duplicate warn 但后加载覆盖 |
| Medium | YAML parser / watcher 复杂度被低估 | 已记录 |
| Medium | 工期按完整版被低估 | 简版优先：先做安装门控 + precedence 读层 + 状态区分；若写回路径能小改兼容，再追加写回阶段 |
| Medium | **R4: 配置优先级 8 层链 vs 计划"3 文件 merge"偏差** | **R6**：按官方 precedence + 本机安装版本探测实际加载顺序；自定义配置目录作为用户设置候选层，只读纳入，不硬编码文件结论 |
| Medium | **R4: 测试文件实际 974 行（非 998）** | 修正行号引用 |
| Medium | **R4: 第 6 个 StateObject 可能影响性能** | 建议 lazy initialization |
| Medium | **R5: mmx-cli symlink 去重** | `~/.claude/skills/mmx-cli` 是 `~/.agents/skills/mmx-cli` 的 symlink（**R8 二次确认**），discovery 时 canonical URL 去重 |
| Medium | **R5: 技能发现路径 6 条（3 全局+3 项目级）** | 首版仅覆盖全局 3 条，UI 标注“全局管理器”范围；自定义配置目录仅影响配置定位，不等于项目级 skill 扫描 |
| Medium | **R6: permission 需要树状归类而不是循环写回** | 父级关闭时子级自动关闭；落盘只做一次最终序列化，不做多轮回写 |
| Medium | **R6: 状态区分不清** | UI/模型拆分 discovered / effective / writable / read-only / overridden / unavailable / installed |
| Medium | **R6: 简版与大改冲突** | 若当前代码接入需要大结构调整，停在只读版，不扩范围 |

### 1.2 官方源码行为模型

| 源码文件 | 确认点 |
|---|---|
| `skill/index.ts` | Discovery pattern 为 `{skill,skills}/**/SKILL.md`；内置 `customize-opencode` 在 disk discovery 前注册；`available()` filter `action !== "deny"`；**R5 补充**：项目级路径（`.opencode/`, `.claude/`, `.agents/`）在 worktree 中向上遍历 |
| `skill/discovery.ts` | `skills.urls` 从远程 `index.json` 拉取；`skills.paths` 扫描额外本地目录 |
| `config/config.ts` | `loadGlobal()` / `globalConfigFile()` 的实际行为需按本机安装版本探测；不得硬编码“某个文件不存在”，而要先做存在性与加载顺序探测，再决定只读展示与写入目标 |
| `config/permission.ts` | `InputSchema = Action \| InputObject`；解析时用 `propertyOrder: "original"` 保留 key 顺序 |
| `config/parse.ts` | `schema()` 用 `decodeUnknownExit(schema)(data, { propertyOrder: "original" })` |
| `config/paths.ts` | `directories()` 返回 multi-level；`files()` 搜索 `opencode.jsonc` + `opencode.json`（jsonc 优先）；如用户设置了自定义配置目录，需作为候选配置层纳入只读探测 |
| `permission/index.ts` | `evaluate()` 委托 `PermissionV2.evaluate()`；`fromConfig()` 展开 config 为 ruleset；`merge()` 拼接 |
| `agent/agent.ts` | 内置 agent defaults：explore 含 `"*": "deny"`；compaction/title/summary 含 `"*": "deny"`；**R5 补充**：scout 也已确认；**R8 确认**：官方 Schema `Config.properties.agent.properties` 列有 scout agent |
| `wildcard.ts` | `match()` 把 `*` → `.*`、`?` → `.`，末尾 ` *` → `( .*)?` |
| `permission.ts` (core) | `evaluate()` 使用 `findLast()` 实现 last-match-wins；default action 为 `"ask"`（code-level fallback） |

**R6 重要补充——官方优先级检测与自定义目录**：
官方文档描述 8 层优先级（低→高）：Remote → Global → Custom → Project → .opencode → Inline → Managed → MDM。UI 与解析层都以这条链作为展示基准；但具体读写目标必须按本机安装版本与实际文件存在性探测，不再硬编码 `config.json` 是否参与。用户设置的自定义配置目录作为候选配置层纳入只读展示，不直接替代官方 precedence。

**R6 重要补充——简版优先**：
只要当前项目结构需要大改，就只保留安装门控 + 只读优先级展示 + 状态区分，不进入写回路径。

**R6 重要补充——oh-my-openagent.json 审计结论**：
该文件（227 行）定义 11 个自定义 agent + 8 个 category 的 model/fallback/skills/permission 配置（hephaestus/oracle/librarian/explore/multimodal-looker/prometheus/metis/momus/atlas/sisyphus-junior/sisyphus）。其中 `skills` 字段为 agent 级白名单（如 oracle 仅可用 `self-development-p, skill-suggester, skill-vetter`），独立于全局 `permission.skill`。无 `permission.skill` 字段，不影响全局技能权限管理；UI 仅做只读标注，不写入。部分 agent（prometheus/atlas/sisyphus）无独立 permission 块，其 skill 行为完全由全局 `permission.skill` 决定。

### 1.3 本地定向核查结果

| 本地项 | 结果 |
|---|---|
| `~/.config/opencode/skills` | 存在 31 个 skill 目录（+ `.DS_Store` = 32 条目） |
| `~/.config/opencode/skill` | 不存在（但方案应支持 future-proof） |
| `~/.agents/skills` / `~/.claude/skills` | 存在 `mmx-cli`；**R8 修正**：`~/.claude/skills/mmx-cli` 是 symlink → `../../.agents/skills/mmx-cli`，非独立副本。canonical URL 去重仍有效 |
| 用户实际 opencode.json | `permission.skill` = string `"allow"`（第 43 行，493 行文件）；`permission` = 27-key object；MCP 段含 5 组 secrets |
| `oh-my-openagent.json` | 227 行，**R7 修正**：11 个自定义 agent（非 12），5 个含独立 permission 块（均不包含 `skill` 字段），无冲突 |
| SafeFileStore 架构 | root 绑定在 `~/Library/Application Support/`，`validate()` 拒绝 root 外路径；`writeCodable` 使用 `sortedKeys`（line 42）——**确认不复用** |
| 当前 App 写入能力 | 仅写入 `~/Library/Application Support/` 内部；写入 `~/.config/opencode/` 是全新能力 |
| **R5: App Sandbox 状态** | ✅ `--disable-sandbox` + ad-hoc codesign → **无沙箱**，自由写入任意路径 |
| **R5: O_EXCL 可行性** | ✅ Darwin `open()` 直接可用，内核级原子排他创建 |
| **R5: oh-my-openagent.json** | ✅ 无 `permission.skill`，无冲突 |
| **R6: OpenCode 本机安装状态** | 需运行时预检；未安装则只读提示，不创建配置 |
| **R8: config.json / opencode.json / opencode.jsonc 真实加载顺序** | 源码 `globalConfigFile()`：`[opencode.jsonc, opencode.json, config.json].find(existsSync)`——第一个存在者胜，不 merge。需在 `OpenCodePaths.swift` 中实现相同逻辑 |
| **R8: 现有 .bak 文件** | `~/.config/opencode/` 下有 37 个历史 .bak（opencode.json×28 + oh-my-openagent.json×7 + AGENTS.md×2），均含明文 MCP secrets |
| **R8: `CaseIterable` 实际不影响** | `Sources/CodexTokenCostApp/` 中无 `CodexDashboardPage.allCases` 使用，TabView 为手动构建，添加 `.skills` case 安全 |
| **R7: 代码适配度** | ✅ **确认可行** — 当前 3-tab (`CodexDashboardPage` 枚举: total/opencode/codex) + 5-StateObject (appPreferencesModel/openCodeModel/codexModel/balanceManager/updateChecker) + `ContentView.toolbarRefreshButton` switch 需新增 `.skills` case；全为增量添加，不触发 Section 15 降级 |
| 测试文件 | 1019 行（`CodexTokenCostCoreTests.swift`）；**R8 修正**：R7 声称 974 行已过时，实际新增 45 行 |
| `Package.swift` | 无外部 SPM 依赖，仅 link sqlite3 + Security framework |

---

## 2. 功能范围

### 2.1 In Scope

| 范围 | 说明 |
|---|---|
| OpenCode 安装预检 | 先确认本机 OpenCode 已安装；未安装时不自动创建 config，只显示安装提示 |
| 官方优先级/自定义 config dir | 按官方 precedence chain 检测有效配置层；提供自定义配置目录设置（仅影响探测与展示） |
| Skills 发现 | 全局三目录 plural + singular 兼容 + `skills.paths`（安全路径内）；**R5 标注**：首版仅全局目录，不扫描项目级路径（`.opencode/` 等） |
| 内置 skill 展示 | `customize-opencode` 标记为 built-in source，只读展示 |
| Remote URLs 检测 | 只读检测 `skills.urls`，展示 warning |
| Manifest 解析与校验 | SKILL.md frontmatter 解析，分级校验（Error/Warning/Info） |
| 权限读取 | 仅读依据官方 precedence 探测到的有效配置目标；从 raw text 抽取 ordered rules |
| 权限展示 | Global configured status + rule chain + agent native defaults matrix（**8 列：Build/Plan/General/Explore/Scout/Compaction/Title/Summary**）+ user agent override + permission 树状归类 |
| 权限写入 | 仅写已存在且通过预检的目标 config；文件不存在时拒绝写入，不自动创建；hash guard + batch transaction + backup + O_EXCL + rollback |
| $schema 版本检测 | Phase 2 新增；未知版本禁用写入 |
| JSON inline comments 检测 | `.json` 文件内含 `//`/`/* */` 标记只读 |
| 安全备份/回滚 | 写入前创建 `.bak-YYYYMMDD-HHmmss-<uuid8>` + O_EXCL tmp + `replaceItemAt` |
| UI 接入 | 新增 Skills tab（第 4 个 tab）；展示 installed / discovered / effective / writable / read-only / overridden / unavailable 状态 + permission tree |
| 测试 | 57 个测试用例覆盖全链路 |
| 文档 | 更新 CHANGELOG/SECURITY/README/开发手册/功能模块清单/架构图/copilot instructions |

### 2.2 Out of Scope

| 范围 | 原因 |
|---|---|
| MCP/provider/agent 写入 | 首版不做 |
| project/managed/MDM config 写入 | 影响范围更大，首版不写 |
| OpenCode 未安装时自动创建配置 | 不做 |
| JSONC 写回 | 保留注释安全 patch 成本高 |
| 全盘扫描 | 只扫描官方固定目录 |
| 安装/删除 skill | 首版只做发现和权限 |
| `skills.urls` 自动拉取 | 首版仅 show warning |
| Agent effective matrix 细化 | 首版展示 8 个 agent（**R8 扩展**） |
| 项目级技能路径（`.opencode/skills/` 等） | 首版定位"全局管理器" |
| 大规模 Settings/Config 架构重构 | 若需要才停在只读版，不强行扩 |
| oh-my-openagent.json `skills` whitelist 编辑 | 独立于 permission 机制，首版只读标注 |

---

## 3. 安全边界

### 3.1 路径边界

| 操作 | 允许 | 禁止 |
|---|---|---|
| 读取 skill | 官方固定全局目录 + singular + 安全的 custom/skills.paths；对每个发现的目录做 `resolvingSymlinksInPath()` 并验证目标路径在允许树内 | 全盘遍历；symlink 指向允许树外的目录（拒绝并记录 warning） |
| 读取 config | 依据官方 precedence + 本机版本探测到的有效配置层（含用户自定义配置目录）只读解析；未安装时不进入写入流程 | 输出完整 config、渲染 secret |
| 写 config | 仅写已安装 OpenCode 且已存在、可解析、通过版本校验的目标 config 文件；不自动创建 | `OPENCODE_CONFIG`、project、managed、未安装环境、不存在的文件 |
| 自定义 config dir | 作为用户设置的候选层，不替代官方 precedence；**安全校验**：(a) 在 `$HOME` 内，(b) `resolvingSymlinksInPath()` 解析后仍在 `$HOME` 内，(c) 拒绝网络/AFP/SMB 挂载路径（`URLResourceKey.volumeIsLocal`） | 盲写路径；接受非本地路径；接受 `$HOME` 外路径 |
| 备份 | `~/Library/Application Support/CodexTokenCost/backups/.bak-YYYYMMDD-HHmmss-<uuid8>`（**R7 修正**：从 config 同目录迁移至沙箱内，防止备份 secret 暴露在 `~/.config/opencode/` 中）；rotate 保留最近 10 份，旧备份 `FileManager.removeItem` 直接删除（**R7-Final 修正**：macOS 无 `shred` 命令，且 APFS+SSD 穿戴均衡使覆写无意义，详见 SECURITY.md） | 写到 config 同目录；写到 `/tmp` |
| 临时文件 | config 同目录 `.tmp.<uuid>`，O_EXCL 独占创建；失败路径（包括 rollback）必须清理残留 tmp | `/tmp` |

**R5 确认：App 构建时使用 `--disable-sandbox`，无 App Sandbox 限制，写入 `~/.config/` 无系统级障碍。**

### 3.2 Secret 保护

| 风险 | 控制 |
|---|---|
| `mcp.*.environment` token | 不展示、不日志、不 diff |
| provider apiKey | 不展示、不日志 |
| raw text scanner 误匹配 | 独立 redaction pass：mcp/provider 段正则替换为 `[REDACTED]` |
| debug 日志 | DEBUG 下也只输出 redacted diff |
| UI 误渲染 | UI 只展示 skill 名称、manifest、permission rules、warning |
| **R7: 备份文件含 secrets** | 备份目录从 config 同目录迁移至 `~/Library/Application Support/CodexTokenCost/backups/`（沙箱内），rotate 时删除旧备份（macOS 无 `shred`，`FileManager.removeItem` 直接删除；APFS+SSD 覆写不可靠，在 SECURITY.md 中注明） |

### 3.3 写回流水线

1. Detect OpenCode installation and active version; if missing, stop at read-only mode and show install CTA.
2. Resolve effective config candidates using official precedence + user custom config dir setting.
3. canonicalize 选中的目标路径。
4. 校验目标路径属于有效 config root 且目标文件已存在；若不存在则拒绝自动创建。
5. 检测 JSONC 注释/`.jsonc`/`.json` 内含非标准 `//` 或 `/* */` 注释 → **改进（R7）**：仅检测字符串上下文**外**的 `//`/`/* */`，避免合法 URL 中的 `//` 误判。检测到→标记只读。
6. 读取原始 bytes，计算 `SHA256` 并记录 `inode` + `mtime`。
7. 独立 redaction pass：mcp/provider 段替换为 `[REDACTED]`。
8. Scanner 从 raw text 抽取 `permission.skill` object 的 ordered members。
9. `JSONSerialization` 解析原始 JSON 做合法性 guard。
10. 确定 migration 路径（absent/string/object）。
11. 构造 ordered text patch，所有 pending changes 合为一次 patch。
12. 生成 redacted preview。
13. 用户确认（含并发修改提示、installed status、effective layer、custom config dir、**R8 新增：热加载限制警告——"⚠️ 权限变更将在 OpenCode 重启后生效"**、**R7 新增：TOCTOU 风险提示**）。
14. **二次读取，比对 hash + inode + mtime**（**R7 增强**：仅 hash 不够，增加 inode/mtime 比对检测 `echo > file` 类覆盖）。若不一致 → 展示 redacted diff（仅显示 changed key paths，mcp/provider 不展开）→ 用户选择"仍然写入（风险自负）"或"取消"。
15. 在 `~/Library/Application Support/CodexTokenCost/backups/` 创建 `.bak-YYYYMMDD-HHmmss-<uuid8>`（**R7 修正**：备份迁移至沙箱内，防止 config 同目录的备份暴露 secrets）。
16. **O_EXCL 写 `.tmp.<uuid>`**（`Darwin.open(path, O_WRONLY|O_CREAT|O_EXCL, 0o600)` → `FileHandle(fileDescriptor:)` → write → close；EEXIST 则换 UUID 重试）。
17. `JSONSerialization` 解析 tmp JSON。
18. Diff guard：确认仅 `permission.skill` 子树变化；**R7 增强**：额外验证原始 JSON ↔ 输出 JSON 在 `permission.skill` 子树外的结构等价（key 集合、嵌套层级一致）。
19. **R8 新增——第三次 TOCTOU 检查**：`replaceItemAt` 之前对原始文件做最后一次 inode+mtime 快速检查。若自 Step 14 以来有变化 → 中止，提示"文件已被外部修改，请重新加载并重试"。这将在 Step 15-19 之间缩小 TOCTOU 窗口。
20. `FileManager.replaceItemAt` 原子替换。**R7 注释**：`replaceItemAt` 不保留 inode，但 config 场景无功能影响。
21. 替换后重新读取解析。
22. 任一步失败 → backup 恢复；**R7 新增**：同步清理残留 `.tmp.<uuid>` 文件；恢复失败 → 高危错误 + 提示备份路径。**R8 增强**：恢复前验证 backup 是合法 JSON（`JSONSerialization` 解析成功）。
23. **R7 新增**：`OpenCodeConfigFileStore.init()` 启动时检测残留 `.tmp.<uuid>` 和孤立 backup → 自动清理。

### 3.4 JSONC 策略

| 状态 | 行为 |
|---|---|
| `opencode.json` 纯 JSON | 可读可写 |
| `opencode.json` 含注释/尾逗号 | 可读，写入禁用 |
| `opencode.json` 含非标准 `//` 或 `/* */` | R4 新增：等效 JSONC，标记只读 |
| `opencode.jsonc` | 可读，写入禁用 |
| 共存 `opencode.json` + `opencode.jsonc` | jsonc 含 `permission.skill` → 写入按钮置灰 + warning |

---

## 4. 官方行为模型

### 4.0 官方配置优先级与运行时探测

- 以官方 8 层 precedence 作为展示/排序基准（Remote → Global → Custom → Project → .opencode → Inline → Managed → MDM）。
- 具体读写目标按本机已安装 OpenCode 的实际版本与文件存在性探测。
- **R8 补充——全局配置加载顺序**：源码 `globalConfigFile()` 按 `[opencode.jsonc, opencode.json, config.json]` 顺序搜索 `~/.config/opencode/` 目录，**第一个存在者胜出**，不 merge。需在 `OpenCodePaths.swift` 中实现相同逻辑。
- 自定义配置目录是用户设置项，只影响候选层与展示，不直接覆盖官方 precedence。
- **R8 补充——OpenCode 热加载限制**：官方 `watcher` 配置仅用于项目文件监听（如 `node_modules`、`.git` 忽略），**不监听 config 文件自身**。config 在启动时通过 `state()` 一次性加载，运行时修改 `opencode.json` 不会自动生效。UI 必须在确认弹窗和状态条中明确提醒用户重启 OpenCode。

### 4.1 Skill 发现路径

**R6 说明：完整路径为 6 条（3 全局 + 3 项目级）。首版仍仅覆盖全局 3 条。**

| Source Kind | Path | 首版范围 |
|---|---|---|
| `globalOpenCode` | `~/.config/opencode/skills/` + singular `skill/` | ✅ |
| `globalClaude` | `~/.claude/skills/` | ✅ |
| `globalAgents` | `~/.agents/skills/` | ✅ |
| `projectOpenCode` | `.opencode/{skill,skills}/**/SKILL.md`（在 worktree 中向上遍历） | ❌ 首版不做 |
| `projectClaude` | `.claude/skills/**/SKILL.md` | ❌ 首版不做 |
| `projectAgents` | `.agents/skills/**/SKILL.md` | ❌ 首版不做 |
| `customConfigDir` | 用户设置的自定义配置目录（若存在，安全路径内） | ✅ |
| `builtIn` | `customize-opencode`（磁盘同名可 override） | ✅ |
| `additionalPaths` | `skills.paths[]` 安全路径内 | ✅ |

### 4.2 Frontmatter schema（分级校验）

| 字段 | 校验等级 |
|---|---|
| `name` | **Error** if missing/invalid/mismatch |
| `description` | **Warning** if missing（源码可加载无 description）；**Error** if >1024 字符 |
| `license` | Info |
| `compatibility` | Info |
| `metadata` | Info |
| unknown fields | Info（保留展示） |

### 4.3 权限值

| 值 | 行为 |
|---|---|
| `allow` | Skill 立即加载 |
| `ask` | 加载前询问 |
| `deny` | Skill 对 agent 隐藏 |
| absent | **"Implicit (Default allow)"** — config-level effective default |

### 4.4 权限匹配

与官方 `PermissionV2.evaluate()` + `Wildcard.match()` 一致：`*` → `.*`、`?` → `.`、末尾 ` *` → `( .*)?`、last-match-wins（`findLast()`）。

### 4.5 Agent Native Defaults Matrix（R5 扩展至 7 列，**R8 扩展至 8 列**）

| Agent | Skill 默认 | 原因 |
|---|---|---|
| `build` | Allow | 无额外限制（default `"*": "allow"`） |
| `plan` | Allow | 同上 |
| `general` | Allow | 同上 |
| `explore` | **Deny** ⚠️ | `"*": "deny"` + 白名单 grep/glob/list/bash/webfetch/websearch/read |
| `scout` | **Deny** ⚠️ | **R8 补全** — 官方 Schema 列有 scout agent，默认 `"*": "deny"` |
| `compaction` | **Deny** ⚠️ | `"*": "deny"` 覆盖所有 |
| `title` | **Deny** ⚠️ | `"*": "deny"` 覆盖所有 |
| `summary` | **Deny** ⚠️ | `"*": "deny"` 覆盖所有 |

### 4.6 权限继承和迁移

| 当前配置 | 迁移 |
|---|---|
| 无 `permission` | 创建 `"permission": { "skill": { "*": "allow", "<skill>": "<action>" } }` |
| `"permission": "allow"` | 迁移为 `{ "*": "allow", "skill": { "*": "allow", ... } }` |
| `"permission.skill": "allow"` | 迁移为 `"skill": { "*": "allow", "<skill>": "<action>" }`（依赖 Phase 0.5 验证） |
| `"permission.skill": object` | exact key 存在则更新；否则末尾追加 |

### 4.7 权限树状归类与单次写回

- `permission` 在 UI 中按树状结构展示：顶层 = tool/group，子层 = pattern rules。
- 父节点关闭时，子节点自动关闭并同步灰化；子节点不再单独保持“开启但父级关闭”的假状态。
- 读取时只计算 effective state，写回时一次性序列化最终树，不做循环写回或逐项回写。
- 若当前代码结构无法以小改支持树状联动，则保留只读展示，不强行写回。

---

## 5. 数据模型设计

### 5.1 Core 目录策略

优先复用 `Sources/CodexTokenCostCore/` 现有结构；只有在简版不受影响且单文件明显过大时，才拆出 `OpenCode/` 子目录。

### 5.2 Core 文件清单

| 文件 | 估算 | 职责 |
|---|---:|---|
| `OpenCodePaths.swift` | 120 行 | 路径解析、OpenCode 安装检测、官方 precedence 解析、custom config dir、canonical path、安全白名单 |
| `OpenCodeSkillManifest.swift` | 180 行 | SKILL.md frontmatter 解析、分级 validation |
| `OpenCodeSkillDiscovery.swift` | 180 行 | 固定目录扫描、source kind、symlink 去重、duplicate aggregation |
| `OpenCodeSkillRules.swift` | 200 行 | permission value、glob matcher、last-match-wins、树状归类、effective state、**8 列 agent matrix**（**R8 扩展**：含 scout） |
| `OpenCodeConfigStore.swift` | 280 行 | 单文件读取 + 版本/安装探测 + effective config root 解析 + raw text ordered rules + redaction + $schema 检测 + hash guard |
| `OpenCodeConfigEditor.swift` | 360 行 | ordered text patch + migration + batch + backup + **O_EXCL（Darwin open）** + rollback + hash guard diff；仅在目标文件已存在且预检通过时写回 |
| `SkillPermissionTextPatcher.swift` | 140 行 | **Phase 0.5 REQUIRED 原型**：JSON text 边界定位、string/object/absent 三态处理、**nested object 前邻边界**；写回功能的前置依赖 |
| `OpenCodeConfigFileStore.swift` | 150 行 | **独立 store**：目标 config 已存在前提下安全读写，路径 validate、atomic write、backup-rotate(keep:10)，绝不使用 `sortedKeys` |
| `OpenCodeConfigWatcher.swift` | 120 行 | 后置 watcher |

### 5.3 App 文件清单

| 文件 | 估算 | 职责 |
|---|---|---:|
| `Stores/OpenCodeSkillsModel.swift` | 200 行 | ObservableObject 状态、installation status、effective config source、custom config dir override、**OPENCODE_CONFIG 检测状态**（**R8 新增**）、pending batch、apply/revert |
| `Views/OpenCodeSkillsPageView.swift` | 520 行 | Skills tab 页面、**8 列 agent matrix**（**R8 扩展**）、installed/effective/writable/read-only/overridden 状态、warnings、确认写入 |
| `Views/ContentView.swift` | 小改 | `CodexDashboardPage` enum 新增 `.skills` case；`TabView` 新增第 4 个 tab；`toolbarRefreshButton` switch 新增 `.skills` case |
| `App/TokenCostApp.swift` | 小改 | 新增 `@StateObject private var openCodeSkillsModel = OpenCodeSkillsModel()`（第 6 个）；传入 `ContentView` 和 `MenuBarView` |
| `Resources/*/Localizable.strings` | 中改 | 新增 Skills 中英双语文案（~80 条字符串） |

---

## 6. UI 设计

### 6.1 页面结构

| 区域 | 内容 |
|---|---|
| Sidebar | 搜索、OpenCode 安装状态、配置来源筛选、custom config dir、状态筛选、统计卡片、skill 列表 |
| Detail | manifest 详情、configured/effective/writable/read-only 状态、agent availability matrix（**Build/Plan/General/Explore/Scout/Compaction/Title/Summary**，**R8 扩展至 8 列**）、permission tree、warnings |
| Toolbar | Refresh、Apply pending（含 count）、Revert pending、只读状态、安装提示 |

### 6.2 状态区分（必须展示）

| 状态 | 含义 |
|---|---|
| installed / not installed | OpenCode 是否已安装 |
| discovered | 该 skill / config 项已在磁盘发现 |
| effective | 该项当前处于实际生效层 |
| writable | 目标文件存在、版本兼容、通过预检，可安全写回 |
| read-only | JSONC / 版本未知 / 未安装 / 目标文件缺失 |
| overridden | 被更高优先级配置或规则覆盖 |
| unavailable | 路径缺失、无权限或格式不可用 |

### 6.3 警告横幅（含 R5/R6 新增）

| 警告 | 触发 |
|---|---|
| JSONC 只读 | config 含注释、`.jsonc`、`.json` 内含 `//`/`/* */` |
| OpenCode not installed | 运行时未检测到 OpenCode，写回禁用 |
| Duplicate skill name | 多目录同名 skill |
| Invalid manifest (Error/Warning) | name/description 不合法 |
| Agent restricts via * deny | 内置 agent 默认隐藏 skill（4 个 agent：explore/compaction/title/summary） |
| **R5: Agent skills whitelist** | oh-my-openagent.json 中 agent 的 `skills` 数组为白名单，仅列出 skill 对该 agent 可用 |
| Higher precedence config | 检测到更高优先级配置 / custom config dir / managed / MDM |
| Schema version unknown | $schema URL 不在已知兼容列表 |
| Missing config target | 目标配置文件不存在，禁止自动创建 |
| JSON inline comments | `.json` 文件内含非标准注释 |
| Config precedence gap | 当前只做简版，只读展示有效层与自定义 config dir；更高优先级可能覆盖 |
| **R5: Scope limitation** | 仅扫描全局目录，不包含项目级技能（`.opencode/` 等） |
| **R8: OpenCode running** | OpenCode 进程检测到正在运行，提示"权限变更将在 OpenCode 重启后生效" |
| **R8: OPENCODE_CONFIG detected** | 在 shell profile 中检测到 `OPENCODE_CONFIG` 环境变量，提示用户确认目标配置路径 |

### 6.4 写入确认

确认弹窗展示：待变更 skill 列表、installed status、effective layer、old→new status、target path、custom config dir、migration 需求、backup path、redacted diff、并发修改警告、batch note。**R8 新增：热加载限制红色警告——"⚠️ 权限变更将在 OpenCode 重启后生效"**。**hash guard 失败时额外展示 redacted changed keys diff + "仍然写入"/"取消"双选项。**

---

## 7. 实施阶段

### Phase 0 — 方案落盘和版本修正

| # | 文件 | 修改 | 状态 |
|---|---|---|---|
| 0.1 | `.sisyphus/plans/skills-manager-v0.7.0.md` | 本方案（R7 Final Audit） | ✅ R7 已落盘 |
| 0.2 | 旧计划 | `skills-manager-plan.md`（v0.5.1）+ `skills-manager-v0.6.0.md` 均标记 superseded | ✅ 已执行 |
| 0.3 | `CHANGELOG.md` | **确认**：Added 预留 + Security 新增 Product Security Posture Change **已存在**；按需补充 R8 audit 结果 | ✅ 已部分完成，按需补充 |
| **0.4** | **`~/.config/opencode/` 旧 .bak 清理** | **R8 新增**：清理现有 37 个历史 .bak 文件（opencode.json×28 + oh-my-openagent.json×7 + AGENTS.md×2），保留最新 3 个 opencode.json.bak 作为应急恢复用，其余 `FileManager.removeItem` 直接删除。原因：所有 .bak 均含明文 MCP secrets，构成安全暴露面 | ⚠️ **R8 新增，待执行** |
| **0.5** | **Phase 0.5 真实文件扫描验证（前置门控）** | **R8 新增**：在开始 Phase 0.5 的 22 个测试场景之前，对**真实** `~/.config/opencode/opencode.json`（非匿名化副本）执行一次**只读 scan**：text scanner 定位所有 `"skill"` key 出现位置，验证有且仅有一个匹配为 `permission.skill` 直系子节点，且不在 MCP secret 值、agent.plan.permission 子树或任何字符串值内部。验证后立即丢弃结果（不保存、不输出）。若真实文件 scan 不通过→Phase 0.5 不可开始，直接激活 Section 15 Fallback | ⚠️ **R8 新增，Phase 0.5 前置条件** |
| 0.6 | `README.md` | **确认**：安全描述更新 + 功能列表新增 **已存在**；按需补充 R8 限制说明 | ✅ 已部分完成 |
| 0.7 | `SECURITY.md` | **确认**：Skills 受限写入安全声明 **已存在**（line 27-37）；按需补充 R7 安全项 | ✅ 已部分完成，按需补充 |
| **0.8** | **`SECURITY.md`** | **R7-Final + R8 增强**：补充 5 项 R7 安全加固 + **R8 新增**：OpenCode 热加载限制说明、OPENCODE_CONFIG 盲区标注、现有 .bak 清理记录、跨卷原子性记录、恢复路径安全要求 | ⚠️ 待执行 |
| **0.9** | **`SECURITY.md`** | **R7-Final 新增**：标注 "JSONC/注释文件只读" 是工具限制，非 OpenCode 规范限制（Schema 含 `"allowComments": true`）；修正备份路径描述 | ⚠️ 待执行 |

### Phase 0.5 — Text Patch 原型验证（**REQUIRED, CRITICAL PATH**，22 个场景）

> **R7 重要修正**：从"可选"更正为 **REQUIRED**。原因：当前用户 `opencode.json` 的 `permission.skill` 是 string `"allow"`（第 43 行），非 object 形态。若跳过此原型验证，Section 15 Fallback Plan 只支持 object 形态写入，意味着 **100% 的当前用户（string 形态）将落入只读模式**，写回功能完全不可用。
>
> string→object migration 是最高风险操作，必须在 ConfigEditor 开发前完成独立验证。
>
> **R7 Final 补充——临时副本隔离（CRITICAL SAFETY PROTOCOL）**：Phase 0.5 的所有 text patch 测试**必须在匿名化副本上进行，绝不可修改用户的真实 `~/.config/opencode/opencode.json`**。操作流程如下：
>
> 1. **创建匿名化副本**：从用户真实的 `~/.config/opencode/opencode.json` 复制一份到 `~/Library/Application Support/CodexTokenCost/prototype/opencode-anonymized.json`，并将所有 secret 值替换为 `[REDACTED]`（`mcp.*.environment`、`mcp.*.headers`、`provider.*.options.apiKey` 等段的值）；其余字段保持原样以保留真实的 JSON 结构（嵌套深度、缩进风格、key 排序）。
> 2. **每次测试操作副本**：对每个测试场景，从匿名化副本 `cp` 到独立临时文件 `~/Library/Application Support/CodexTokenCost/prototype/test-<uuid>.json`，所有 read/patch/write 均针对临时文件。
> 3. **测试后清理**：每个场景结束后删除临时文件。
> 4. **绝不 touch 真实 config**：真实 `~/.config/opencode/opencode.json` 在整个 Phase 0.5 期间保持只读不写。
>
> 验证方法（每场景）：
> - **(a)** text patch 后 `JSONSerialization` 可解析为合法 JSON
> - **(b)** 对照官方 Schema `https://opencode.ai/config.json` 验证 `permission.skill` 子树合法性（`PermissionRuleConfig = anyOf(PermissionActionConfig, PermissionObjectConfig)`；`PermissionObjectConfig` 的 `additionalProperties` 值必须为 `"allow"`/`"ask"`/`"deny"` 之一）
> - **(c)** 原始 JSON ↔ 输出 JSON 除 `permission.skill` 子树外结构等价（key 集合、嵌套层级一致）
> - **(d)** diff 输出仅 `permission.skill` 子树变化
> - **(e)** 可选：在沙箱环境中设置 `OPENCODE_CONFIG=<test-file>` 启动 OpenCode 验证可正常解析（高风险场景才需要）

| # | 测试场景 |
|---|---|
| 0.5.1 | 定位 value 边界（单行 string value） |
| 0.5.2 | 单行变多行替换（缩进保持） |
| 0.5.3 | 验证逗号处理（前导/尾部逗号） |
| 0.5.4 | 用匿名化 493 行真实 config 做 text patch |
| 0.5.5 | absent/string/object 三态 + 追加/更新/多次追加 |
| 0.5.6 | 空 permission `{}` |
| 0.5.7 | skill 在 permission 最后一个 key（无尾部逗号） |
| 0.5.8 | skill 在 permission 第一个 key（无前导逗号） |
| 0.5.9 | 幂等性：重复追加不产生重复 key |
| 0.5.10 | 组合迁移：string→object + 追加 rule |
| **0.5.11** | **R5 新增：skill 前邻为多行嵌套对象**（如 `"bash": {...70+行}`）→ 精确跳过嵌套边界 |
| **0.5.12** | **R5 新增：skill 前邻为嵌套对象 + 后邻为简单值**（真实 config 第 43 行场景） |
| **0.5.13** | **R7-Final 新增：跨行 string value**（`"skill":\n    "allow"`，多行格式） |
| **0.5.14** | **R7-Final 新增：permission 为空字符串** `"permission": ""`（Schema 非法→检测并报错） |
| **0.5.15** | **R7-Final 新增：permission.skill 非字符串非对象值**（`true`/`null`/数值 `42`）→检测并报错 |
| **0.5.16** | **R7-Final 新增：多 `"skill"` key 定位歧义**（agent.*.permission.skill vs 顶层 permission.skill）→ scanner 需精确定位 permission 直系子节点 |
| **0.5.17** | **R7-Final 新增：permission 同级出现重复 key**（非法 JSON→报错，不可静默合并） |
| **0.5.18** | **R7-Final 新增：UTF-8 BOM 头文件**（影响 byte offset 计算） |
| **0.5.19** | **R7-Final 新增：混合缩进**（space+tab 混用→text patch 生成一致缩进） |
| **0.5.20** | **R7-Final 新增：文件末尾有/无换行符**（影响新 key 追加位置） |
| **0.5.21** | **R7-Final 新增：`replaceItemAt` 权限继承**（新文件是否保留原始文件的 owner/group/POSIX permissions） |
| **0.5.22** | **R7-Final 新增：skill 目录名含 Unicode**（如中文名→wildcard 匹配和 JSON key Unicode 规范化 NFC/NFD） |

**FALLBACK GATE**：任一项不通过 → 激活 Section 15 Fallback Plan，仅支持 object 形态。

### Phase 1 — Core 基础模型

`OpenCodePaths.swift`：**R8 增强**——增加 shell profile scanner（`.zshrc`/`.bash_profile`/`.zprofile`）检测 `OPENCODE_CONFIG` export；增加 `globalConfigFile()` 等价实现（`[opencode.jsonc, opencode.json, config.json].find(existsSync)` 搜索顺序）

验收：no broad scan、singular support、symlink canonical 去重、built-in detection、安装状态/precedence 探测、分级 validation、glob matcher 与官方一致、duplicate detection、permission 树状归类、**8 列 agent matrix** 正确、**R8：`globalConfigFile()` 搜索顺序正确**、**R8：`OPENCODE_CONFIG` shell profile 检测功能正常**。

### Phase 2 — Config Store 只读解析

`OpenCodeConfigStore.swift` + `OpenCodeConfigFileStore.swift`：**仅读有效配置目标** + raw text ordered rules + redaction pass + **安装/版本/precedence 检测** + 自定义配置目录 + **$schema 版本检测** + hash guard 准备。

验收：config 不泄密、schema 兼容、ordered rules 顺序正确、$schema 未知版本禁用写入。

### Phase 3 — Config Editor 受限写入

`OpenCodeConfigEditor.swift`：文件存在性检查 + JSONC/inline-comments detect + ordered text patch（依赖 Phase 0.5）+ migration + batch + hash guard（含 diff display）+ backup + **O_EXCL（Darwin open）** + replace + rollback + redacted preview；仅在 OpenCode 已安装且目标文件存在时启用。

验收：只改允许子树、顺序不变、hash guard 失败展示 diff + "仍然写入"选项、backup 防碰撞、O_EXCL 独占创建（EEXIST 重试）、失败回滚、secrets redacted、不会自动创建目标文件、**R8：第三次 TOCTOU 检查在 replaceItemAt 前执行**。

### Phase 4-7 — Watcher / App Model / UI / App 接入

（标准实现，参见详细计划；若实现需要大改结构，则只保留 Phase 1/2 的只读版本）

> **R7-Final 注意——`CaseIterable` 兼容性排查**：`CodexDashboardPage` 遵循 `CaseIterable`。在添加 `.skills` case 前，需排查代码中所有 `.allCases` 遍历点（如 TabView 动态生成、设置页 tab 列表等），确保不会自动将新 tab 暴露到未预期的 UI 位置。搜索模式：`CodexDashboardPage.allCases`、`\.allCases` 在 `Sources/CodexTokenCostApp/` 内。
>
> **R7-Final 注意——`AppLocalization` 非枚举注册制**：`AppLocalization.text("tab.skills")` 是通过 `Bundle.localizedString(forKey:)` 在 `.strings` 文件中隐式查找，不需要在枚举中注册。新增 key 只需在 `Resources/{zh-Hans,en}.lproj/Localizable.strings` 中添加 key=value 条目即可。`AppLocalization` 实际定义在 `Sources/CodexTokenCostCore/Localization.swift:23`（非 `App/AppLocalization.swift`）。

### Phase 8 — Tests

`Tests/CodexTokenCostCoreTests/OpenCodeSkillsTests.swift`：**57 个测试用例**（含 R4 10 个 + R5 保留）。

### Phase 9-10 — 文档更新 / 验收

更新 CHANGELOG/SECURITY/README/docs/copilot-instructions/localization。**R8**：SECURITY.md 补充热加载限制、OPENCODE_CONFIG 盲区、跨卷原子性、恢复路径安全要求。自动验收（`swift test` + `swift build -c release`）+ 手动验收 17 项。

---

## 8. 本地化 Key 规划

新增 key 分组：Tab、Header、Search/filter、Status、Source、Warning（含 R4：`skills.warning.schemaUnknown`、`skills.warning.jsonInlineComments`、`skills.warning.configPrecedenceGap`；**R5 新增**：`skills.warning.agentSkillsWhitelist`、`skills.warning.scopeGlobalOnly`；**R6 新增**：`skills.warning.opencodeNotInstalled`、`skills.warning.missingConfigTarget`、`skills.warning.customConfigDirMissing`；**R7 新增**：`skills.warning.toctouRisk`、`skills.warning.symlinkOutsideRoot`；**R8 新增**：`skills.warning.openCodeRunning`、`skills.warning.openCodeConfigDetected`、`skills.warning.restartRequired`）、Action、Confirm、Error（含 `skills.error.hashGuardConflict`）、Detail、Agent Column（**8 列，R8 扩展**）、State、Setting。

**R7 说明**：以上为 key 列表，实际需在 `Resources/en.lproj/Localizable.strings` 和 `Resources/zh-Hans.lproj/Localizable.strings` 中分别添加对应中英文值，约 100 条字符串（~50 key × 2 locale），含 R7 新增的 warning/error/status key（`skills.warning.toctouRisk`、`skills.warning.symlinkOutsideRoot`、`skills.status.backupRelocated` 等）。`tab.skills` key 通过 `AppLocalization.text()` 在 `.strings` 文件中隐式注册，无需枚举。

---

## 9. 风险收敛

| 风险 | 状态 | 控制 |
|---|---|---|
| config secret 泄露 | 收敛 | 不展示 + redaction pass + DEBUG 只输出 redacted |
| JSON key 顺序改变 | 收敛 | raw text scanner + text patch |
| JSONC 注释丢失 | 收敛 | JSONC 只读 + **R7 改进**：上下文感知检测避免 URL 中 `//` 误判 |
| 并发覆盖 | 收敛 | hash guard + **R7 增强**：inode+mtime 比对 + diff display + "仍然写入" |
| 多 pending 多次写入 | 收敛 | batch transaction |
| text patch 破坏 JSON | 收敛 | Phase 0.5 原型（12 场景）+ Section 15 Fallback |
| SafeFileStore 不兼容 | 收敛 | 独立 `OpenCodeConfigFileStore` |
| **R6: 配置加载/写入行为版本差异** | 收敛 | 运行时探测实际加载顺序，按本机安装版本和官方 precedence 交叉核对，不硬编码 `config.json` 结论 |
| $schema 版本不兼容 | 收敛 | Phase 2 版本检测 |
| string→object migration 失败 | 已备降级 | Section 15 Fallback Plan（**R7 修正**：影响面从"约 30% 用户"更新为"100% 用户（string 形态）"） |
| **R5: App Sandbox 兼容性** | ✅ **已消除** | `--disable-sandbox`，无沙箱限制 |
| **R5: O_EXCL 可行性** | ✅ **已消除** | Darwin `open()+O_EXCL` 完全可行 |
| **R5: oh-my-openagent 冲突** | ✅ **已消除** | 无 `permission.skill`，`skills` 白名单独立 |
| **R6: OpenCode 未安装** | 收敛 | install gate；未安装只读提示，不自动创建配置 |
| **R6: permission 树状归类/状态区分** | 收敛 | 父级关闭自动带子级关闭；UI 区分 discovered / effective / writable / read-only / overridden / installed |
| **R6: 简版与大改冲突** | ✅ **已消除(R7)** | code-fit 确认 3-tab+5-StateObject 增量添加可行，不触发降级 |
| **R7: TOCTOU 竞态窗口** | 收敛 | hash guard + inode+mtime 比对；用户确认弹窗标注并发风险 |
| **R7: JSONC 注释误判** | 收敛 | text scanner 上下文感知检测，区分字符串内外 |
| **R7: Symlink 攻击向量** | 收敛 | discovery 阶段对每个目录做 `resolvingSymlinksInPath()` + 允许树内验证 |
| **R7: 备份 Secret 残留** | 收敛 | 备份迁移至 `~/Library/Application Support/` 沙箱内 + rotate 安全删除 |
| **R7: O_EXCL tmp 文件残留** | 收敛 | rollback 增加 tmp 清理；init() 启动时检测残留 |
| **R7: 写回中断恢复** | 收敛 | `OpenCodeConfigFileStore.init()` 启动时检测残留文件并清理 |
| **R7: 自定义 config dir 安全校验** | 收敛 | $HOME 内 + symlink 解析 + `volumeIsLocal` 拒绝网络挂载 |
| **R7: 文本补丁结构等价性** | 收敛 | diff guard 增加"除 permission.skill 外结构等价"断言 |
| **R7: mmx-cli 副本 vs symlink** | 收敛 | canonical URL 去重，标注"symlink duplicate"（**R8 二次确认**：确认为 symlink） |
| **R8: OpenCode 热加载不支持** | 收敛 | UI 警告 + 进程检测状态条；重启前变更不生效 |
| **R8: OPENCODE_CONFIG 盲区** | 收敛 | shell profile scanner + UI 手动输入框 |
| **R8: 现有 .bak secret 暴露** | 收敛 | Phase 0.4 清理步骤 |
| **R8: scout agent 遗漏** | ✅ **已修正 (R8)** | Agent matrix 8 列 |
| **R8: 双重 TOCTOU 窗口** | 收敛 | Step 18→19 第三次 inode+mtime 检查 |
| 第 6 个 StateObject 性能 | 收敛 | 建议 lazy initialization |
| mmx-cli symlink 去重 | 收敛 | canonical URL 去重 |
| 技能发现路径 6 条→首版 3 条 | 接受 | UI 标注"全局管理器"范围 |

---

## 10. 最终执行顺序

0. **Phase 0** — 方案落盘（本文件 R8 Final Audit）+ 旧计划标记 superseded + 文档确认补充 + **R8：现有 .bak 清理 + Phase 0.5 前置真实文件 scan**
1. **Phase 0.5** — Text Patch 原型（**REQUIRED**，**R8 扩展至 23 个场景包含真实文件 scan**；失败则无写回功能，100% 用户只读）
2. Phase 1 — Core parser/discovery/rules + 单测
3. Phase 2 — ConfigStore + ConfigFileStore 读取 + 安装/版本/precedence 检测 + redaction + 单测
4. Phase 3 — ConfigEditor（依赖 Phase 0.5）+ 单测
5. Phase 4-8 — Watcher / Model / UI / App 接入 / 剩余 Tests（code-fit 已通过，不触发降级）
6. Phase 9-10 — 文档 + 验收

---

## 11. 不变更清单

| 文件/区域 | 说明 |
|---|---|
| `Package.swift` | 不新增依赖 |
| MCP / Provider / Keychain / Browser cookie | 不读写 |
| OpenCode SQLite / Codex JSONL | 不修改 |
| `SafeFileStore.writeCodable` | **不复用**（sortedKeys 破坏顺序） |
| 现有测试文件 | 不追加到 `CodexTokenCostCoreTests.swift` |
| `oh-my-openagent.json` | 只读标注，不写 |

---

## 12. 预计工作量

| Phase | 时间 | 备注 |
|---|---|---:|
| Phase 0 旧计划标记 + 文档确认补充 + .bak清理 | 30 min | R8 新增 .bak 清理 + 真实文件 scan |
| Phase 0.5 Text Patch 原型 | 4-6 h | **REQUIRED**——23 个场景（22 + 1 真实 scan） |
| Phase 1 Core | 2 h | |
| Phase 2 ConfigStore + FileStore | 2-3 h | |
| Phase 3 ConfigEditor | 3-4 h | 依赖 Phase 0.5 通过 |
| Phase 4-7 Watcher/Model/UI/接入 | 4-6 h | code-fit 已确认可行 |
| Phase 8 Tests | 3-4 h | |
| Phase 9 Docs | 2 h | |
| Phase 10 验收 | 1-2 h | |
| **总计** | **21-29 h**（若 Phase 0.5 失败→仅只读版 15-19h） |

---

## 13. SDD Cross-Check (R8 Final)

| Check | Result |
|---|---|
| Intent | Pass，聚焦 Skills 管理器 |
| Evidence | Pass，R1-R8 全证据链：librarian + explore + oracle + oh-my-openagent + sandbox + code-fit + **R8 官方 docs 全量交叉核查** + **本地 4-agent 并联审计** + TOCTOU/symlink/JSONC/backup/hot-reload/OPENCODE_CONFIG 6 项安全边界验证 |
| Scope | Pass，安装门控 / 官方 precedence / custom config dir / permission tree / state distinctions / Phase 0.5 REQUIRED / O_EXCL / hot-reload 限制 / OPENCODE_CONFIG 检测 / fallback |
| Regression | Medium，57 个测试用例 |
| Tests | Planned，覆盖全链路 |
| Dependency | **R8 确认**：当前项目 3-tab + 5-StateObject 适配增量添加；`CaseIterable` 不影响（无 `.allCases`）；**Agent matrix 8 列** |
| Security | Pass，安装门控 + redaction + **R8 增强**：双 TOCTOU inode+mtime + symlink 解析验证 + 备份沙箱迁移 + 启动残留清理 + 自定义目录安全校验 + 现有 .bak 清理 + hot-reload 限制声明 |
| Fallback readiness | Pass，Section 15 完整降级路径；影响面准确标注为 100% |

---

## 14. SDD Change Report (R7 Final)

**R7 终版审核——基于第 7 轮交叉核查（本地 opencode.json 直接审计 + 项目全量 code-fit 复核 + 4 项安全边界深度验证），补充以下修正：**

**R7 Blocking / High**：
- Phase 0.5 从"可选"更正为 **REQUIRED (CRITICAL PATH)**：当前 100% 用户为 string `"allow"` 形态，跳过则写回功能完全不可用
- TOCTOU 竞态窗口：hash guard 增加 inode+mtime 比对；用户确认弹窗标注并发风险
- Symlink 攻击向量：discovery 阶段对每个目录做 symlink 解析 + 允许树内验证
- JSONC 注释检测改进：上下文感知避免字符串内 `//` 误判
- 文档状态同步：Phase 0.3-0.5 改为"确认当前内容 + 按需补充"
- oh-my-openagent.json 审计修正：11 agent（非 12），mmx-cli 为 symlink（**R8 二次确认**：`~/.claude/skills/mmx-cli → ../../.agents/skills/mmx-cli`）
- 旧计划引用修正：`v0.6.0/plan`（不存在）→ `skills-manager-v0.6.0.md` + `skills-manager-plan.md`

**R7 Medium**：
- 备份 secret 残留：备份从 config 同目录迁移至 `~/Library/Application Support/` 沙箱内 + rotate 安全删除
- O_EXCL tmp 文件残留：rollback 增加 tmp 清理；init() 启动时检测残留
- 写回中断恢复：`OpenCodeConfigFileStore.init()` 启动时检测并清理残留
- 自定义配置目录安全校验：$HOME 内 + symlink 解析 + `volumeIsLocal`
- `O_CLOEXEC` 标志注释：非 fork/exec 场景无安全收益，保留并注释说明
- `replaceItemAt` inode 行为：在 SECURITY.md 中记录
- 文本补丁后结构等价性：diff guard 增加"除 permission.skill 外结构等价"断言
- Fallback 影响面修正：从"约 30%"更正为"100%（当前均为 string 形态）"
- code-fit 确认：3-tab + 5-StateObject 增量添加可行，不触发 Section 15 降级

**R7 已消除风险**：
- "简版与大改冲突"：code-fit 确认通过 → ✅ 已消除
- "代码适配度待确认"：确认可行 → ✅ 已消除

**R7-Final 终版补充（基于最后一轮交叉核查 + 用户反馈）**：
- **Phase 0.5 沙箱隔离协议（CRITICAL）**：明确要求所有 text patch 测试在匿名化副本上进行（`~/Library/Application Support/CodexTokenCost/prototype/`），绝不修改真实 config；增加 10 个补充测试场景（0.5.13-0.5.22），覆盖跨行 value、非法值检测、多 key 定位歧义、BOM/Unicode/缩进混合等边界
- **Schema 验证集成**：Phase 0.5 每场景需对照官方 `https://opencode.ai/config.json` 验证 `permission.skill` 子树合法性（`PermissionRuleConfig` schema）
- **macOS `shred` 不可用**：备份旋转改为 `FileManager.removeItem` 直接删除，SECURITY.md 标注 APFS+SSD 物理覆写不可靠
- **`O_CLOEXEC` 统一移除**：Swift macOS App 无 fork/exec，该标志无安全收益，从 `open()` flags 中移除（消除计划内部矛盾）
- **Phase 0 文档任务扩展**：新增 0.6（SECURITY 5 项 R7 安全加固）、0.7（JSONC 只读工具限制标注 + 备份路径修正）、0.8（物理覆写限制标注）
- **`CaseIterable` 兼容性排查**：`CodexDashboardPage.allCases` 遍历点需在添加 `.skills` 前排查
- **`AppLocalization` 注册机制纠正**：确认是 `Bundle.localizedString(forKey:)` 隐式注册，非枚举注册制
- **旧计划标记执行**：`skills-manager-plan.md` + `skills-manager-v0.6.0.md` 头部已添加 ⚠️ SUPERSEDED 标记
- **本地化 key 估算修正**：40→50 key（含 R7 新增 warning/error/status key）

---

**R8 终版补充（基于官方 docs + config.json Schema 全量交叉核查 × 本地 4-agent 并联审计 + Oracle 安全审计）**：

**R8 Blocking / High**：
- **OpenCode 热加载限制**：官方 docs 零提及 config hot-reload；`watcher` 仅用于项目文件；源码 `state()` 一次性初始化。UI 增加红色 "⚠️ 重启后生效" 警告 + 进程检测状态条
- **OPENCODE_CONFIG 环境变量盲区**：官方 confirm `OPENCODE_CONFIG` 为第 3 优先级配置层；GUI App 看不到 shell profile 中的 `export`。Phase 1 增加 shell profile scanner（`.zshrc`/`.bash_profile`/`.zprofile`）+ UI 手动输入框
- **现有 37 个 .bak 文件 secret 暴露**：Phase 0 新增 Step 0.4 清理步骤（保留最新 3 个，其余删除）
- **Phase 0.5 匿名化掩盖真实边缘情况**：Phase 0 新增 Step 0.5 真实文件只读 scan 前置门控，scene 总数从 22 扩展至 **23**
- **内置 scout agent 补全**：Agent matrix 从 7 列扩展为 **8 列**（Build/Plan/General/Explore/Scout/Compaction/Title/Summary）
- **写回流水线双重 TOCTOU**：Step 18→19 之间增加第三次 inode+mtime 快速检查，缩小第二个 TOCTOU 窗口至微秒级
- **mmx-cli 部署方式二次修正**：R7 误判为"独立副本"，R8 `ls -la` 确认 `~/.claude/skills/mmx-cli → ../../.agents/skills/mmx-cli` 为 symlink
- **测试文件行数修正**：文档声称 974 行→实际 1019 行（+45 行，新增测试）
- **`globalConfigFile()` 搜索顺序**：Section 4.0 和 Phase 1 `OpenCodePaths.swift` 中增加 `[opencode.jsonc, opencode.json, config.json].find(existsSync)` 等价实现要求

**R8 Medium**：
- **恢复路径安全性增强**：Step 21 恢复前增加 backup JSON 合法性验证（`JSONSerialization` 解析）
- **跨卷原子性记录**：backup 与 config 目录在标准 macOS 安装中位于同一 APFS 卷，跨卷场景在 SECURITY.md 记录为已知限制
- **`CaseIterable` 确认无影响**：`Sources/` 中无 `CodexDashboardPage.allCases` 使用，TabView 为手动构建
- **`CodexAppPaths` vs `TokenCostPaths` 命名修正**：文档引用的 `CodexAppPaths` 实际为 `TokenCostPaths`

**R8 验证方法**：`https://opencode.ai/docs/config/` + `/permissions/` + `/skills/` + `/config.json` Schema 全量交叉核查 × 4-agent 并联本地审计 + Oracle 深度安全审计（8 个领域）

---

## 15. Fallback Plan（CRITICAL PATH ESCAPE HATCH）

### 15.1 激活条件

| 触发条件 | Fallback | 影响 |
|---|---|---|
| Phase 0.5 string→object 验收不通过 | 仅支持 object 形态 | **R7 修正**：当前 100% 用户为 string `"allow"` 形态（非"约 30%"），fallback 意味着首次发布写回功能对所有用户不可用；string 形态仅可只读展示。**R7-Final**：22 个测试场景（含 10 个新增边界场景）中任一项不通过即激活 |
| `$schema` URL 未知 | 禁用写入 | 保持只读 safe harbor |
| OpenCode 未安装 | 仅显示安装提示 + 只读发现 | 不创建任何配置文件 |
| 当前项目结构需要大改 | 仅保留只读版 | **R7 确认**：不触发——code-fit 通过 |

### 15.2 Object-Only Fallback

- UI：string 形态 skill toggle 置灰 + 醒目标语 + "复制迁移模板"按钮
- 功能：移除所有 string→object migration 路径
- 测试：string migration 测试跳过，新增 `testWriteDisabledForStringFormSkill`
- 恢复：v0.7.1 重新实现或等待 OpenCode 原生支持

### 15.3 Fallback 不影响的功能

Skill 发现、Manifest 解析、权限读取/展示、Agent matrix、只读 warnings、Backup/rollback（object 形态生效时）、Secret redaction、文件不存在拒绝写入。

### 15.4 简版只读降级

- 如果 OpenCode 未安装、配置目标缺失、或当前项目接入点无法小改适配，则发布简版只读模式。
- 简版只读模式只保留：安装提示、官方 precedence 展示、自定义配置目录只读设置、permission 树状归类展示、状态区分、warning 横幅。
- 简版只读模式不做：自动创建配置、迁移写回、项目级/managed/MDM 写入。

---

## 16. R8 Final Round Audit Summary（终版审核总结）

### 16.1 执行摘要

R8 终版审核在 R7 基础上新增：OpenCode 官方 docs 全量交叉核查（config/permissions/skills + config.json Schema）+ 本地 4-agent 并联审计 + Oracle 8 领域安全审计。**核心结论：方案可执行，不触发 Section 15 降级。2 项高风险限制（热加载/OPENCODE_CONFIG 盲区）已纳入 UI 设计，不影响功能可用性。**

### 16.2 R8 新增风险发现（共 9 项）

| 优先级 | 数量 | 关键项 |
|---|---|---|
| 🔴 P0 | 5 | **OpenCode 热加载限制**（UI 警告解决）、**OPENCODE_CONFIG 盲区**（shell scanner 解决）、**现有 37 .bak secret 暴露**（Phase 0.4 清理）、**Phase 0.5 匿名化掩盖边缘情况**（Phase 0.5 真实 scan 前置门控）、**双重 TOCTOU 窗口**（Step 18→19 第三次检查） |
| 🟡 P1 | 3 | **scout agent 补全**（8 列 matrix）、**恢复路径安全增强**（backup JSON 验证）、**跨卷原子性记录**（SECURITY.md） |
| 🟢 P2 | 3 | mmx-cli symlink 事实修正、测试行数修正、globalConfigFile 实现明确化 |

### 16.3 安全边界加固清单（R8 扩展至 9 项）

| # | 加固项 | 变更 |
|---|---|---|
| 1 | TOCTOU 防护 | hash guard SHA256 → SHA256+inode+mtime 三重比对 + **R8: 第二次 TOCTOU 窗口第三次检查** |
| 2 | Symlink 验证 | discovery 阶段 `resolvingSymlinksInPath()` + 允许树内验证 |
| 3 | JSONC 检测 | 上下文感知检测（区分字符串内外） |
| 4 | 备份安全 | 从 config 同目录迁移至沙箱 + **R8: Phase 0.4 清理现有 37 个暴露备份** |
| 5 | 会话恢复 | `OpenCodeConfigFileStore.init()` 启动残留检测与清理 |
| 6 | 自定义目录 | `$HOME` 内 + symlink 解析 + `volumeIsLocal` 三重校验 |
| 7 | 结构等价 | diff guard 增加原始↔输出除 permission.skill 外结构等价断言 |
| **8** | **热加载限制** | **R8 新增**：UI 确认弹窗 + 状态条双重提醒 "重启后生效" |
| **9** | **OPENCODE_CONFIG** | **R8 新增**：shell profile scanner + UI 手动配置 + 优先使用检测到的路径 |

### 16.4 交叉核查结论（R8 更新）

| 核查项 | 结论 |
|---|---|
| opencode.json `permission.skill` 形态 | string `"allow"`（第 43 行）——确认 |
| oh-my-openagent.json agent 数量 | 11——确认 |
| mmx-cli 部署方式 | **symlink** `~/.claude/skills/mmx-cli → ../../.agents/skills/mmx-cli`——**R8 二次确认修正** |
| 项目 code-fit | 3-tab + 5-StateObject 增量添加可行——**不触发降级** |
| `CaseIterable` 影响 | 无 `CodexDashboardPage.allCases` 使用——**确认无影响** |
| 现有 .bak 文件 | 37 个——**Phase 0.4 清理** |
| 测试文件行数 | 1019 行（非 974）——**R8 修正** |
| 官方 Schema Agent 列表 | 8 个内置 agent（含 scout）——**R8 补全** |
| config 热加载行为 | 不支持——**UI 警告解决** |
| OPENCODE_CONFIG | GUI App 不可见——**shell scanner 解决** |
| 文档状态 | CHANGELOG/README/SECURITY 已部分完成——Phase 0 改为确认+补充模式 |

---

> **方案状态：R8 终版审核通过，Phase 0 前置修正已完成（旧计划标记、文档同步清单、现有 .bak 清理、真实文件 scan 前置门控就绪），Phase 0.5 可进入。**
> 
> **码适配度**：当前项目结构（3-tab + 5-StateObject）适合增量式添加，不触发 Section 15 简版只读降级。`CaseIterable` 确认无影响。
>
> **Agent Matrix**：扩展至 **8 列**（Build/Plan/General/Explore/Scout/Compaction/Title/Summary），与官方 Schema 一致。
>
> **写回功能可用性**：完全依赖 Phase 0.5 text patch 原型的 **23 个场景**（22 基础 + 1 真实文件 scan 前置门控）全部通过。若任一失败，首次发布仅支持只读模式。
>
> **热加载限制**：OpenCode 不支持 config 热加载。UI 必须在确认弹窗和状态条中明确提醒用户重启 OpenCode。此项限制不影响功能正确性，但影响用户体验。
>
> **OPENCODE_CONFIG 盲区**：Phase 1 shell profile scanner + UI 手动配置已覆盖此场景。
>
> **Phase 0.5 安全约束**：所有 text patch 测试必须在匿名化副本上进行；Phase 0.5 Step 0 必须先通过真实文件只读 scan 前置门控。
>
> **下一稿版本**：v0.7.1（实施后根据实际开发反馈修订）
