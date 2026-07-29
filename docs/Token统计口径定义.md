# Token 统计口径定义

> 本文档是项目中所有 Token 相关统计指标的唯一事实来源（Single Source of Truth）。  
> 所有页面（CodexPageView、OpenCodePageView/DetailView、TotalView、MenuBarView）和热力图必须遵循本文档定义的口径。

---

## 1. 定义速查表

| 指标 | 英文 | 含义 | OpenCode 来源 | Codex 来源 |
|------|------|------|-------------|-----------|
| **全量 Token** | Gross Total Tokens | 含缓存的全量 token | `$.tokens.total`（含 cacheRead + cacheWrite） | `inputTokens + outputTokens + reasoningOutputTokens`（含 cachedInput） |
| **实际输入** | Actual Input Tokens | 计费口径的输入 token | `$.tokens.input`（SQLite 字段已是非缓存值） | `max(inputTokens - cachedInputTokens, 0)` |
| **缓存输入** | Cached Input Tokens | 缓存命中、免计费部分 | N/A（字段已分离为 `cache.read` / `cache.write`，不参与计费） | `cachedInputTokens` |
| **输出** | Output Tokens | 模型生成的 token | `$.tokens.output` | `outputTokens` |
| **推理** | Reasoning Tokens | CoT / thinking token | `$.tokens.reasoning` | `reasoningOutputTokens` |
| **实际总量** | Actual Total Tokens | **计费总量** = 实际输入 + 输出 + 推理 | `input + output + reasoning` | `actualInput + output + reasoning` |

---

## 2. 口径说明

### 2.1 OpenCode（SQLite 管线）

OpenCode 的 SQLite 数据库中 `$.tokens.input` 字段**已是非缓存值**（即 OpenCode 在写入时已将缓存命中部分排除在外）。因此：

- `totalActualTokens` = `input + output + reasoning`
- `totalActualInputTokens` = `input`（无需再减 cacheRead 或 cacheWrite）
- `cache.read` / `cache.write` 仅供展示参考，不参与计费 token 计算

**日历日聚合**：SQL 查询使用 `date(time_created/1000, 'unixepoch', 'localtime')` 将毫秒时间戳转为当前机器时区的日历日字符串（`yyyy-MM-dd`）。所有按日聚合的指标（趋势图、热力图、详情表日期列）均遵循此本地时区边界。`DashboardAnalytics` 中的 `chartDateFormatter` 使用 `en_US_POSIX` locale 解析该日期字符串，不涉及时区转换。

### 2.2 Codex（JSONL 管线）

Codex 的 JSONL 日志中 `inputTokens` **包含缓存部分**。因此：

- `totalActualInputTokens` = `max(totalInputTokens - totalCachedInputTokens, 0)`
- `totalActualTokens` = `totalActualInputTokens + totalOutputTokens + totalReasoningOutputTokens`
- Codex 无 `cacheWrite` 字段，不做 cache write 减法

### 2.3 两管线不能简单统一

两条管线的 `actualInputTokens` 公式本质不同，不能强行统一。但两端的 `actualTokens` 在语义上等价——都是"计费口径的 total token"。

---

## 3. 各页面使用对照

| 页面 / 卡片 | 显示指标 | 数据来源 | 
|---|---|---|
| CodexPageView summaryCard #1 | Actual Tokens | `summary.totalActualTokens` |
| CodexPageView summaryCard #2 | Actual Input | `summary.totalActualInputTokens` |
| OpenCodePageView DetailView overview | Actual Tokens | `analytics.overview.totalActualTokens` |
| TotalView overviewCard #4 | Total Actual Tokens | `combinedTotalActualTokens` = `oc.totalActualTokens + cx.totalActualTokens` |
| TotalView openCodeCard #1 | Actual Tokens | `openCodeSummary.totalActualTokens` |
| TotalView codexCard #1 | Actual Input | `summary.totalActualInputTokens` |
| MenuBar summary card | Total Actual Tokens | `combinedTotalActualTokens` |
| Hot Heatmap | Daily merged actual tokens | OpenCode: `input+output+reasoning` / Codex: `actualTokens` |
| DetailView 明细表 | 全量原始行（含排序/分页） | `sortedDetailRows(sortField:direction:)` 基于 `rawRows` 全量过滤后数据集排序，分页在 UI 层截取 |
| 堆叠条形图 | 每日各模型 total token 堆叠 | `stackedSeries` 取 top-8 模型 + Other，覆盖全量 `rawData` 日期范围 |

---

## 4. Ollama Cloud 缓存读估算（Cache-Read Estimation）

> 本功能自动生效，无需开发者模式。触发条件见 §4.1：仅当 Provider 为 `ollama-cloud`、模型已标准化为 `deepseek-v4-flash` 或 `deepseek-v4-pro`、且 `cacheRead == 0` 且 `input > 0` 时自动触发估算。

### 4.1 触发条件

当同时满足以下所有条件时，触发估算：

- Provider 为 `ollama-cloud`
- 模型已标准化为 `deepseek-v4-flash` 或 `deepseek-v4-pro`
- `cacheRead == 0`（真实的缓存读数据缺失）
- `input > 0` 且 `input.isFinite`（存在有效的输入 token）

估算仅在**逐行扫描**时对满足上述条件的原始行触发。不满足条件的行（非 ollama-cloud provider、非 DeepSeek V4 模型、已有真实 cacheRead、或 input 为 0/非有限值）直接跳过，使用真实值。估算值累加到 `ProviderAccumulator.estimatedCacheRead` 中，不覆盖源数据。

### 4.2 数据来源

缓存命中率基于 **2026 年 7 月观测快照**：

| 模型 | 快照 cacheRead | 快照 input | 命中率 rate |
|------|---------------|-----------|------------|
| deepseek-v4-flash | 553,686,784 | 600,792,157 | 553686784 ÷ 600792157 |
| deepseek-v4-pro | 1,476,491,904 | 1,550,614,127 | 1476491904 ÷ 1550614127 |

> ⚠️ **快照时效性**：上述比率为 2026 年 7 月观测值，编译期硬编码。随 Ollama Cloud 缓存基础设施演进将逐步失真。建议每季度复核或当 Ollama Cloud 发布重大基础设施变更时重新采集快照。更新流程：采集新观测期 cacheRead/input → 修改 `DashboardAnalytics.swift` 中 `ollamaDeepSeekCacheReadSnapshotRates` → 更新本表格 → 运行测试。

### 4.3 估算公式

```
rate = snapshot_cacheRead / (snapshot_input + snapshot_cacheRead)
multiplier = rate / (1 − rate) = snapshot_cacheRead / snapshot_input
estimate = input × multiplier
```

估算值 `estimate` 即为 `estimatedCacheReadTokens`。

### 4.4 安全边界

- **估算值永不写入源数据**：`estimatedCacheRead` 仅在运行时计算管道中存在于 `ProviderAccumulator` 内存累加器中，不写入 SQLite、JSONL 或任何持久化文件
- **不影响实际用量/排名**：`ProviderRankRow` 和 `ModelComparisonRow` 中的 `actualTokens`（计费口径）仍使用真实 `input + output + reasoning`，不含估算缓存；`cost` 计算仅基于真实 `cacheRead`，估算值不参与成本计算
- **不影响 `cacheSavedCost`**：`cacheSavedCost` 仅使用真实的 `cacheRead` 计算，不因估算值而膨胀
- **缓存命中率公式**：`cacheHitRate = displayedCacheRead / (totalInputTokens + displayedCacheRead)`，其中 `displayedCacheRead = 真实 cacheRead + 估算 cacheRead`。分母为输入 token 与展示缓存读之和，而非全量 total。含估算时命中率使用展示值计算
- **仅影响展示口径**：估算值仅用于 `CacheSummary.cacheReadTokens`（展示缓存总量含估算）、`CacheSummary.cacheHitRate`（命中率含估算）、`ProviderCacheRow`（含估算的展示值）、趋势图 tooltip（额外展示 `estimatedCacheReadTokens`）
- **TotalView 总览页标注**：`overview.openCode.cacheTokens` 卡片使用 `DashboardPayload.Summary.totalCacheTokens`（真实值，不含估算），当检测到 payload 含 Ollama Cloud 估算数据时，subtitle 切换为"不含 Ollama Cloud 缓存估算"显式标注
- **TaskClassification cacheHeavy 含估算**：分类引擎对 ollama-cloud 行使用估算后的 cacheRead 判断 cacheHeavy 规则，但分类结果仅用于详情表行标签展示，不参与计费/排名

### 4.5 UI 标注

所有含估算值的 UI 元素均被显式标记：

- 缓存区卡片标题切换为"缓存（含估算）"中英文变体
- 每条 Provider 缓存行中，估算值以独立数值和 `estimated` 标签展示
- 趋势图 tooltip 中估算缓存读以独立 `mint` 色行显示
- TotalView 缓存 tokens 卡片 subtitle 标注"不含 Ollama Cloud 缓存估算"（仅含估算数据时显示）
- DetailView 明细表每行追加任务分类标签（`.unclassified` 不渲染）

---

## 5. 全局报告范围成本口径（Reporting Cost）

> 本文档 §1-§4 定义 token 用量口径；§5 定义费用口径中的全局报告范围成本分摊规则。

### 5.1 核心概念

| 概念 | 说明 |
|------|------|
| **Provider 独立订阅周期** | 每个 Provider 拥有独立的 `periodStart`/`periodEnd`（包含式日历日，起止均计入）、`periodGranularity`（`.day` 或 `.month`）和 `hasPeriodTracking` 开关。`periodTotalCost(for:)` 按粒度折算该 provider 的完整周期总成本。关闭 `hasPeriodTracking` 或起止日期缺失/无效时回退 `monthlyUSD`（月费口径） |
| **全局报告范围** | `reportingRangeMode`（`allAvailable`/`currentMonth`/`last30Days`/`custom`）定义全局报告窗口。`resolveReportingRange(mode:customBounds:payload:)` 解析为 `(start, end)` 包含式整日范围 |
| **规范总成本** | `reportingCostBreakdown(payload:reportingStart:reportingEnd:)` 是唯一规范入口，输出 `ReportingCostBreakdown`（`totalCost` + `fixedCostByProvider` + `uncoveredUsageByProviderKey`） |

### 5.2 分摊算法

```
Phase 1 — 固定订阅分摊（每个 provider 独立计算）：
  对每个已启用固定订阅的 provider：
    - hasPeriodTracking = true 且周期有效且与报告范围重叠：
        cycleTotalCost = periodTotalCost(for:)  // 完整周期总成本
        overlapDays = inclusiveCalendarDays(max(periodStart, reportStart), min(periodEnd, reportEnd))
        cost = cycleTotalCost × overlapDays / cycleIncludedDays
    - 无重叠（overlapDays = 0）：
        cost = 0
    - 无周期跟踪 / 起止缺失 / 无效日期：
        cost = monthlyUSD  // 回退月费口径

Phase 2 — 未覆盖 API 用量：
  筛选 rawData 中日期落在报告范围内的行，重新聚合 providerUsageCosts
  对未被 Phase 1 覆盖的 provider key，取其 raw/synthetic cost 加入总成本
```

### 5.3 关键规则

- **零重叠贡献 0**：provider 的 `hasPeriodTracking = true` 且订阅周期与报告范围完全不重叠时（`overlapDays = 0`），该 provider 的固定订阅成本为 0（不回退月费）。其 API 用量进入 Phase 2 按量计算
- **范围内 API 进入 Phase 2**：Phase 2 筛选 `rawData` 中日期落在报告范围内的行（`dayStart...dayEnd` 包含式整日边界），重新聚合 `providerUsageCosts`。未被 Phase 1 覆盖的 provider key 取其 raw/synthetic cost 加入总成本
- **缺失/无效/未跟踪回退月费**：`hasPeriodTracking = false`、`periodStart`/`periodEnd` 为 nil、或 `start > end` 时，该 provider 的固定订阅成本按完整 `monthlyUSD` 计入（不按报告范围折算），保持向后兼容
- **包含式日历日**：起止日期均计入天数。同一天 = 1 天。`inclusiveCalendarDays(from:to:)` 使用 `Calendar.autoupdatingCurrent` 的 `startOfDay` 边界
- **原生 DatePicker 直接输入**：`BillingSectionView` 中 provider 的起止日期使用原生 SwiftUI `DatePicker`（`displayedComponents: .date`）作为直接输入控件，不做额外日期转换或偏移
- **`combinedTotalCost` 兜底**：`combinedTotalCost(payload:)` 优先调用 `reportingCostBreakdown`；当 payload 无法形成有效报告范围时（如空数据），回退 `combinedMonthlyCost`（传统月费口径）

### 5.4 与旧口径的关系

| 口径 | 入口 | 适用场景 |
|------|------|---------|
| `combinedMonthlyCost` | 传统月费口径 | 无报告范围设置时兜底；总览页默认展示 |
| `combinedPeriodCost` | 所有 provider 周期总成本之和 | 开发者模式总览页/菜单栏副文本 |
| `reportingCostBreakdown` | 全局报告范围规范总成本 | 设置页配置报告范围后，总览页/菜单栏使用 `combinedTotalCost` |
| `periodTotalCost(for:)` | 单个 provider 完整周期总成本 | 设置页周期卡片摘要展示 |

---

## 6. 变更历史

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-06-14 | v1.0 | 初始版本。统一 TotalView / MenuBarView / Heatmap 的 Actual Token 口径为计费总量（actualInput + output + reasoning）。 |
