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

---

## 4. 变更历史

| 日期 | 版本 | 说明 |
|------|------|------|
| 2026-06-14 | v1.0 | 初始版本。统一 TotalView / MenuBarView / Heatmap 的 Actual Token 口径为计费总量（actualInput + output + reasoning）。 |
