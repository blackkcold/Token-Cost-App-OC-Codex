# Token 统计口径定义

> 本文档是项目中所有 Token 相关统计指标的唯一事实来源（Single Source of Truth）。  
> 所有页面（CodexPageView、OpenCodePageView/DetailView、TotalView、MenuBarView）和热力图必须遵循本文档定义的口径。

---

## 1. 定义速查表

| 指标 | 英文 | 含义 | OpenCode 来源 | Codex 来源 |
|------|------|------|-------------|-----------|
| **全量 Token** | Gross Total Tokens | 含缓存的全量 token | `$.tokens.total`（含 cacheRead + cacheWrite） | `inputTokens + outputTokens + reasoningOutputTokens`（含 cachedInput） |
| **实际输入** | Actual Input Tokens | 原始兼容口径的输入 token | `$.tokens.input`（通常为非缓存值；Ollama Cloud 例外见 §4） | `max(inputTokens - cachedInputTokens, 0)` |
| **缓存输入** | Cached Input Tokens | 缓存命中、免计费部分 | N/A（字段已分离为 `cache.read` / `cache.write`，不参与计费） | `cachedInputTokens` |
| **输出** | Output Tokens | 模型生成的 token | `$.tokens.output` | `outputTokens` |
| **推理** | Reasoning Tokens | CoT / thinking token | `$.tokens.reasoning` | `reasoningOutputTokens` |
| **实际总量** | Actual Total Tokens | **原始兼容总量** = 实际输入 + 输出 + 推理 | `input + output + reasoning` | `actualInput + output + reasoning` |
| **净实际 Token** | Net Actual Tokens | `实际总量 − Ollama 估算缓存读`；用于详情展示、Provider/模型 API 等值成本分母与 Relay `cost` | `overview.netActualTokens` / rank rows | N/A |

> `实际总量` 保留为原始兼容毛值；`净实际 Token` 不写回源数据。对于 Ollama Cloud 估算行，API 等值成本使用净 input 与 `reported + estimated` cache read；订阅、自定义费用和 raw db cost 的优先级不变。TotalView、MenuBar 与 Codex 管线仍保留毛值统计。

---

## 2. 口径说明

### 2.1 OpenCode（SQLite 管线）

OpenCode 的 SQLite 数据库中 `$.tokens.input` 字段**已是非缓存值**（即 OpenCode 在写入时已将缓存命中部分排除在外）。因此：

**Ollama Cloud 例外**：未上报缓存读的 Ollama `input` 是含隐藏缓存的 gross input。原始字段与毛值总览保持不变；对 §4 规定的目标行做内存拆分，并以拆分结果计算净 Token 与 API 等值成本。这里的“实际”仍是兼容性统计指标，不代表已测得 Ollama 的真实账单。

- `totalActualTokens` = `input + output + reasoning`
- `totalActualInputTokens` = `input`（无需再减 cacheRead 或 cacheWrite）
- `cache.read` / `cache.write` 不计入 `actualTokens`，但可按各自费率参与 API 等值成本

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
| Relay cost section | 净计费 Token | Provider/模型 `netActualTokens`，与 section 内 `costUSD` 同口径 |
| Relay usage section | 原始用量 Token | Provider/模型 `actualTokens` 毛值，保持配额/来源语义 |
| Relay heatmap section | Daily field-total tokens | `displayActualTokens + displayedCacheRead + cacheWrite`（从 gross input 内拆分；本地 Hot Heatmap 保持原始 actual） |
| DetailView 明细表 | 全量原始行（含排序/分页） | `sortedDetailRows(sortField:direction:)` 基于 `rawRows` 全量过滤后数据集排序，分页在 UI 层截取 |
| 堆叠条形图 | 每日各模型 total token 堆叠 | `stackedSeries` 取 top-8 模型 + Other，覆盖全量 `rawData` 日期范围 |

### 3.1 模型归组（Model Categorization）

模型饼图、堆叠图与价格对比统一使用 `ModelPricingCatalog.resolve(provider:model:)` 产出的 `canonicalKey` 聚合；模型价格对比仍使用 `(normalizedProviderKey, canonicalKey)` 复合身份，避免同名模型跨 Provider 混价。

标准化与归并顺序：

1. 小写 + 去空白 + 空格转连字符
2. 去除 `provider/` 前缀（取最后一个 `/` 之后）
3. 精确 alias 匹配（`deepseek-chat` → `deepseek-v4-flash`、`deepseek-reasoner` → `deepseek-v4-pro`、`minimax-m2.7-highspeed` → `minimax-m2.7`）
4. **尾部构建/发行修饰归并**：仅剥离 `:1017`、`:0731`、`:cloud` 这类 tag，以及 `-cloud`、`-fast`、`-preview`、`-latest`、`-edge`、`-thinking` 与 `-YYYYMMDD` 日期后缀，得到家族键
5. **语义版本不合并**：`v4` 与 `v4.1` 是两个模型（ollama-cloud 实测价 0.22 vs 0.15），不互相折叠
6. **`-free` / `-exp` 不剥离**：`-free` 永远独立成行，绝不继承付费价；`-exp` 代表实验模型，保留自身身份

> 例：`deepseek-v4.1-flash:1017` → `deepseek-v4.1-flash`；`deepseek-v4-flash:0731-cloud` → `deepseek-v4-flash`；`glm-5.3-flash:cloud` → `glm-5.3-flash`；`deepseek-v4.1-flash-free` 保持独立。

价格解析（按 Provider 作用域短路）：手动覆盖 → 原始 ID 精确命中 → alias → 逐级剥离修饰后的命中 → 家族键命中 → 同 Provider 最长前缀命中 → 跨 Provider 唯一家族 → 未定价。旧版 `normalizeModelName` 仅保留给 Ollama 缓存读估算资格判断（§4），不再参与计费分组。


---

## 4. Ollama Cloud 缓存读估算（Cache-Read Estimation）

> 本功能自动生效，无需开发者模式。触发条件见 §4.1：仅当 Provider 为 `ollama-cloud`、模型已标准化为 `deepseek-v4-flash` 或 `deepseek-v4-pro`、且 `cacheRead == 0` 且 `input > 0` 时自动触发估算。

### 4.1 触发条件与聚合粒度

当同时满足以下所有条件时，触发估算（唯一资格谓词：`OllamaCloudCacheEstimation.isEligibleOllamaEstimate(provider:model:cacheRead:input:)`，所有调用点统一经由该谓词判断）：

- Provider 归一化后（trim + 小写）为 `ollama-cloud`（实测 OpenCode 数据恒为小写，大小写/空白变体同样兼容）
- 模型已标准化为 `deepseek-v4-flash` 或 `deepseek-v4-pro`
- `cacheRead == 0`（真实的缓存读数据缺失）
- `input > 0` 且 `input.isFinite`（存在有效的输入 token）

估算仅在**逐行扫描**时对满足上述条件的原始行触发。不满足条件的行（非 ollama-cloud provider、非 DeepSeek V4 模型、已有真实 cacheRead、或 input 为 0/非有限值）直接跳过，使用真实值。估算值累加到 `ProviderAccumulator.estimatedCacheRead` 中，不覆盖源数据。

**三值口径**：估算相关量统一命名为 `realCacheRead`（真实值，源数据）、`estimatedCacheRead`（运行时估算）、`displayedCacheRead = real + estimated`（展示和 API 等值计价口径）。`cacheSavedCost` 继续只使用 real 值，避免把推测节省包装成已确认节省。

**SQL 聚合粒度（cache_read_bucket）**：`TokenDatabaseClient` 的用量查询在 `GROUP BY usage_date, model_id, provider_id` 基础上追加 `cache_read_bucket` 列分组：ollama-cloud 且 `tokens.cache.read == 0` 的消息归 bucket 0，其余归 bucket 1。这样同一 (日期， 模型， Provider) 组合的混合缓存消息会拆成两条聚合行——估算只对 bucket 0（无真实缓存读）的聚合行触发，避免"同组内已有真实缓存读却被整体估算"的口径污染。`cache_read_bucket` 仅作 GROUP BY key，值 0/1 不被下游读取。为此 `DashboardPayload.RawRow.id` 追加缓存桶后缀（`|0` / `|1`），保证分桶行在 SwiftUI `ForEach` 中身份唯一。

**防循环约束**：`OllamaCloudCacheEstimation.Context` 只接受当前分析 payload 的非 Ollama 原始行作为参考，绝不读取已估算的输出。每次分析只构建一次，详情分类复用同一上下文。

### 4.2 数据来源

优先使用当前分析 payload（即调用方已选择的报告范围）的同标准化模型、非 Ollama 参考行：`rate = ΣcacheRead / Σ(input + cacheRead)`。有效行要求 input/cacheRead 有限、input ≥ 100、cacheRead ≥ 0、分母有限，且行比例严格位于 `(0.01, 0.99)`。至少 3 条有效聚合行且 gross 总量 ≥ 1,000 才使用运行时率；累加溢出或不满足门槛时使用以下 **2026 年 7 月快照兜底**。样本数指日期/模型/provider 聚合桶，不是独立请求数。上下文记录 rate/source/sampleCount/grossTokens，来源为 runtime 或 snapshot。

这是经过截断筛选的跨 Provider 参考值，不是 Ollama 实测率，也不是统计置信度保证。报告范围变化会改变估算；模型别名及不同 Provider 工作负载仍可能引入偏差。

| 模型 | 快照 cacheRead | 快照 gross input（含缓存） | 命中率 rate |
|------|---------------|-----------|------------|
| deepseek-v4-flash | 553,686,784 | 600,792,157 | 553686784 ÷ 600792157 |
| deepseek-v4-pro | 1,476,491,904 | 1,550,614,127 | 1476491904 ÷ 1550614127 |

> ⚠️ **快照时效性**：上述比率为 2026 年 7 月观测值，编译期硬编码。随 Ollama Cloud 缓存基础设施演进将逐步失真。建议每季度复核或当 Ollama Cloud 发布重大基础设施变更时重新采集快照。更新流程：采集新观测期 cacheRead/input → 修改 `DashboardAnalytics.swift` 中 `ollamaDeepSeekCacheReadSnapshotRates` → 更新本表格 → 运行测试。

### 4.3 估算公式

```
rate = runtimeRate ?? snapshot_cacheRead / snapshot_grossInput
estimate = ollamaGrossInput × rate
displayInput = input − estimate
displayActual = input + output + reasoning − estimate
displayedCacheRead = realCacheRead + estimate
```

估算值 `estimate` 即为 `estimatedCacheReadTokens`。

rate 必须有限且在 `(0,1)`，estimate 必须有限且 > 0，`input - estimate` 必须有限且 > 0，否则 estimate=0、不拆分。已有真实 cacheRead 的 bucket-1 和其他模型不拆分。ProviderCacheRow 原 `inputTokens/actualTokens/usageTokens` 不变，新增计算型 `displayInputTokens/displayActualTokens/displayedUsageTokens`；TrendPoint 原 actualTokens 不变，新增计算型 displayActualTokens。

守恒以原始字段合计为基准：`displayActual + displayedCacheRead + cacheWrite = input + output + reasoning + realCacheRead + cacheWrite`（浮点容差）。源 `tokens.total` 可能与字段合计不同，保留 overview.totalTokens，不静默改写；该差异由回归测试覆盖。旧 `cacheReadMultiplier` API 仅保留源码兼容，估算不再调用它。

### 4.4 诚实性门控（D8）

单一资格谓词只回答"这一行**是否可能**是未上报缓存"；是否**真的**未上报，由报告范围内的 Ollama 证据决定：

- 预扫描所有 `ollama-cloud` 且 `cacheRead > 0` 的聚合桶，记录 `(归一化模型, 日期)` 键集合。
- 资格判据追加 `!(归一化模型, 日期) ∈ 已上报集合`。
- 语义：某 `(归一化模型, 日期)` 只要**存在任何** `cacheRead > 0` 的桶，说明 Ollama 当天在该模型上确实在上报缓存，那么同日的 `cacheRead == 0` 桶就是**真实无缓存请求**，**不得估算**。

门控**按 Provider 限定**：非 Ollama Provider 在同模型同日的缓存上报不能作为 Ollama 上报的证据（两者上报行为互相独立）。否则 `deepseek`/`opencode-go` 等参考 Provider 的缓存会错误地压制 Ollama 估算。

边界行为（可接受）：缓存纪元**之前**的日期会整体估算（含其中的真实无缓存请求）；纪元**切换当天**会整体不估算（含其中的漏报行）。两者量级都很小。

### 4.5 安全边界

- **估算值永不写入源数据**：`estimatedCacheRead` 仅在运行时计算管道中存在于 `ProviderAccumulator` 内存累加器中，不写入 SQLite、JSONL 或任何持久化文件
- **毛值兼容、净值计价**：`ProviderRankRow`/`ModelComparisonRow.actualTokens` 保留真实毛值；新增 `netActualTokens` 用于 tokens/$ 分母。API 等值成本使用 `displayInput` 与 `real + estimated` cache read
- **不影响 `cacheSavedCost`**：`cacheSavedCost` 仅使用真实的 `cacheRead` 计算，不因估算值而膨胀
- **缓存命中率公式**：`cacheHitRate = displayedCacheRead / (displayInputTotal + displayedCacheRead)`，等价分母为 `rawInputTotal + realCacheReadTotal`，不重复加入隐藏缓存。Provider 缓存条同样使用展示输入。
- **影响范围受控**：估算值用于缓存展示、趋势 tooltip、Provider/模型 API 等值成本、tokens/$ 排行与 Relay `cost`；不影响订阅覆盖、raw db cost、源数据和 `cacheSavedCost`
- **TotalView 总览页标注**：`overview.openCode.cacheTokens` 卡片使用 `DashboardPayload.Summary.totalCacheTokens`（真实值，不含估算），当检测到 payload 含 Ollama Cloud 估算数据时，subtitle 切换为"不含 Ollama Cloud 缓存估算"显式标注
- **TaskClassification cacheHeavy 含估算**：分类引擎对 ollama-cloud 行使用估算后的 cacheRead 判断 cacheHeavy 规则，但分类结果仅用于详情表行标签展示，不参与计费/排名
- **Relay 双口径**：`cost.providers/models.tokens` 使用 net，与 `costUSD` 对齐；`usage.providers/models.tokens` 保持 gross。热力图每日 `tokens = displayActualTokens + displayedCacheRead + cacheWrite`；`trend.actualTokens` 保持原始 actual。schema、Contract 版本和 Android 解码结构不变。
- **分类上下文**：单行 classify 默认快照；批量 classify 默认从传入 rows 构建 Context，也可显式注入。DetailView 使用 cachedAnalytics 的同一 Context。分类仅影响标签。

### 4.6 UI 标注

所有含估算值的 UI 元素均被显式标记：

- 缓存区卡片标题切换为"缓存（含估算）"中英文变体
- 每条 Provider 缓存行中，估算值以独立数值和 `estimated` 标签展示
- 趋势图 tooltip 中估算缓存读以独立 `mint` 色行显示
- TotalView 缓存 tokens 卡片 subtitle 标注"不含 Ollama Cloud 缓存估算"（仅含估算数据时显示）
- DetailView 总览网格在存在估算时新增"净实际 Token"卡片，副标题注明已扣估算量与"展示口径，非计费"；毛值"实际 Token"卡片保持原值原位置，二者并列
- DetailView 明细表对参与估算的 `input` 单元格追加青色警示图标，hover 提示原始值未变
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
