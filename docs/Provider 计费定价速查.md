# Provider 计费定价速查（内置快照）

> 来源：各 Provider 官方定价页 / 第三方定价聚合。本文同时记录代码内置快照的适用边界；不承诺等同实时账单。
> 单位：USD / 1M tokens
>
> **运行时已不再以本表计费**：模型排行价格来自 models.dev 目录（见 `docs/模型价格目录与排名口径.md`），本表仅作人工参考与离线兜底快照。Provider 级订阅/兜底成本仍按旧口径计算，不随本表更新跳变。

---

## Anthropic Claude

| 层级 | 模型 | Input | Output | 缓存读 (10%) | 缓存写 5min (1.25x) | 缓存写 1h (2x) |
|---|---|---|---|---|---|---|
| Haiku | Haiku 4.5 | $1.00 | $5.00 | $0.10 | $1.25 | $2.00 |
| Sonnet | Sonnet 4.6 | $3.00 | $15.00 | $0.30 | $3.75 | $6.00 |
| Opus | Opus 4.7 | $5.00 | $25.00 | $0.50 | $6.25 | $10.00 |

**缓存写是溢价项** — 首次写入多付 25%~100%，后续读省 90%。

---

## Google Gemini

| 层级 | 模型 | Input | Output | 缓存读 | 缓存写 | 长上下文 (>200K) |
|---|---|---|---|---|---|---|
| Lite | 2.5 Flash-Lite | $0.10 | $0.40 | $0.01 (90% off) | 等同 Input | 无溢价 |
| Lite | 3.1 Flash-Lite (GA) | $0.25 | $1.50 | $0.025 (90% off) | 等同 Input | 无溢价 |
| Flash | 2.5 Flash | $0.30 | $2.50 | $0.03 (90% off) | 等同 Input | 无溢价 |
| Flash | 3 Flash | $0.50 | $3.00 | $0.05 (90% off) | 等同 Input | 无溢价 |
| Pro | 2.5 Pro | $1.25 | $10.00 | $0.125 (90% off) | 等同 Input | $2.50/$15 |
| Pro | 3.1 Pro | $2.00 | $12.00 | $0.20 (90% off) | 等同 Input | $4.00/$18 |

> 缓存写无溢价，但按量有**存储费**：Lite/Flash $1/1M tok/hr，Pro $4.50/1M tok/hr。

---

## DeepSeek（历史静态近似）

| 层级 | 模型 | Cache Miss Input | Cache Hit Input | Output | 缓存写 |
|---|---|---|---|---|---|
| Flash | V4-Flash | $0.14 | **$0.0028** | $0.28 | **不存在** |
| Pro | V4-Pro | $0.435 | **$0.003625** | $0.87 | **不存在** |

> 上表是 App 为兼容既有数据保留的历史静态近似，不是实时官方报价。当前官方价格包含时段差异，而本项目只有日聚合数据，无法精确还原请求发生时刻；因此代码不会把该表宣称为精确账单。

### Ollama Cloud 下 DeepSeek V4 缓存读缺失估算

Ollama Cloud 代理的 DeepSeek 模型在 token 报告中**不返回 cacheRead**（始终为 0），无法直接衡量缓存命中率。App 自动对 `ollama-cloud` Provider 的 `deepseek-v4-flash` 和 `deepseek-v4-pro` 两个标准化模型启用缓存读估算，无需开发者模式。触发条件如下：

- **数据来源**：当前分析 payload 内非 Ollama 同模型原始行的 `ΣcacheRead/Σ(input+cacheRead)`；至少 3 条有效聚合行且 gross ≥1,000，不足或溢出时回退 2026-07 快照。过滤规则与偏差说明见《Token统计口径定义》§4。
- **命中率快照**：deepseek-v4-flash `rate ≈ 553686784 ÷ 600792157 ≈ 0.9216`；deepseek-v4-pro `rate ≈ 1476491904 ÷ 1550614127 ≈ 0.9523`
- **估算公式**：Ollama input 已含隐藏缓存，`estimatedCacheRead = input × rate`，`displayInput = input − estimatedCacheRead`；快照分母是含缓存 gross input。
- **触发条件**：仅当 `provider == ollama-cloud`、`model` 为标准名称（deepseek-v4-flash/pro）、`cacheRead == 0`、`input > 0`，**且该 `(归一化模型, 日期)` 在报告范围内没有任何 `cacheRead > 0` 的 Ollama 桶**时
- **净成本口径**：API 等值成本以 `displayInput` 计 input、以 `realCacheRead + estimatedCacheRead` 计 cache read；gross `actualTokens` 和源数据不变，`cacheSavedCost` 仍只基于真实 cacheRead
- **Provider profile**：`deepseek`/`deepseek-api-cn` 使用 DeepSeek 历史近似；`opencode`/`opencode-go`/`ollama-cloud` 使用 OpenCode Zen 快照，其中 Ollama 仅作 Zen 等值比较；未知 Provider 不默认继承 Zen 定价
- **未建模项**：DeepSeek 峰谷时段无法从日聚合行恢复。若未来需要精确直连账单，必须引入请求级时间戳或 Provider 实账，而不是继续扩展单一静态表

---

## OpenAI GPT

| 层级 | 模型 | Input | Output | 缓存读 | 缓存写 |
|---|---|---|---|---|---|
| Nano | GPT-4.1 Nano | $0.10 | $0.40 | $0.025 (75% off) | 不存在 |
| Nano | GPT-5.4 Nano | $0.20 | $1.25 | $0.02 (90% off) | 不存在 |
| Mini | GPT-4.1 Mini | $0.40 | $1.60 | $0.10 (75% off) | 不存在 |
| Mini | GPT-5.4 Mini | $0.75 | $4.50 | $0.075 (90% off) | 不存在 |
| Standard | GPT-4.1 (1M ctx) | $2.00 | $8.00 | $0.50 (75% off) | 不存在 |
| Standard | GPT-5.4 (272K ctx) | $2.50 | $15.00 | $0.25 (90% off) | 不存在 |
| Pro | GPT-5.5 (1M ctx) | $5.00 | $30.00 | $0.50 (90% off) | 不存在 |

> OpenAI 无缓存写溢价，自动 prompt caching。Batch API 所有模型统一 50% off。

---

## 订阅 / Token Plan 档位（App 默认选项）

> App 总成本仍以 USD/月为统一口径；人民币档位按当前内置汇率 ¥7.2 ≈ $1 折算。若官方价格变更，可在设置页选择「自定义 USD 月费」。

### OpenCode

| 档位 | 费用 | App 处理 |
|---|---:|---|
| OpenCode Go | $10/月 | 固定月费；首月 $5 只作促销说明，不作为默认值 |
| OpenCode Zen | 按量计费 | 无固定月费；如需纳入总成本，用自定义月费 |

### ChatGPT / Codex

| 档位 | 费用 | App 处理 |
|---|---:|---|
| ChatGPT Plus | $20/月 | Codex 默认订阅口径 |
| ChatGPT Pro | $200/月 | 固定月费预设 |
| Business Codex | 按量计费 | 无固定月费；如需纳入总成本，用自定义月费 |

### Ollama Cloud

| 档位 | 费用 | App 处理 |
|---|---:|---|
| Ollama Free | $0 | 默认口径；轻量云端用量 + 单模型并发 |
| Ollama Pro | $20/月 | 50x Free 云端用量；3 模型并发；$200/年 |
| Ollama Max | $100/月 | 5x Pro 云端用量；10 模型并发 |

> Ollama 用量按 GPU 时间计费（非固定 token 数），有 5 小时 session + 7 天 weekly 双窗口限额。用量追踪门控在开发者模式下；启用后可在余额监控设置中从 Edge / Chrome / Brave / Arc 浏览器导入 session cookie，或手动输入 Cookie，并存储到系统 Keychain。

### MiniMax Token Plan

| 档位 | 月费 | 额度 |
|---|---:|---|
| Starter 标准版 | ¥29/月 | M2.7 600 次请求/5小时 |
| Plus 标准版 | ¥49/月 | M2.7 1,500 次请求/5小时 |
| Max 标准版 | ¥119/月 | M2.7 4,500 次请求/5小时 |
| Plus 极速版 | ¥98/月 | M2.7-highspeed 1,500 次请求/5小时 |
| Max 极速版 | ¥199/月 | M2.7-highspeed 4,500 次请求/5小时 |
| Ultra 极速版 | ¥899/月 | M2.7-highspeed 30,000 次请求/5小时 |

### Xiaomi MiMo Token Plan

| 档位 | 中国区月费 | 海外月费 | 中国区年付 | 海外年付 | Credits（月） | Credits（年） |
|---|---:|---:|---:|---:|---:|---:|
| Lite | ¥39/月 | $6/月 | ¥411.84/年 | $63.36/年 | 4.1B | 49.2B |
| Standard | ¥99/月 | $16/月 | ¥1045.44/年 | $168.96/年 | 11B | 132B |
| Pro | ¥329/月 | $50/月 | ¥3474.24/年 | $528/年 | 38B | 456B |
| Max | ¥659/月 | $100/月 | ¥6959.04/年 | $1056/年 | 82B | 984B |

> 2026-05-27 起生效：Credits 额度大幅增加（5-8 倍），价格不变。

MiMo Credit 消耗规则：

| 模型 | Cache Hit | Cache Miss (Input) | Output |
|---|---|---|---|
| mimo-v2.5 | 2 Credits | 100 Credits | 200 Credits |
| mimo-v2.5-pro | 2.5 Credits | 300 Credits | 600 Credits |

夜间（0:00-8:00 北京时间）消耗系数 0.8x。V2 系列（mimo-v2-pro、mimo-v2-omni）已于 2026-06-01 自动路由至 V2.5，将于 2026-06-30 弃用。

---

## 四家对比总览

| 维度 | Anthropic | Gemini | DeepSeek | OpenAI |
|---|---|---|---|---|
| 最低 Input | $1.00 (Haiku) | **$0.10** (Flash-Lite) | **$0.14** (V4-Flash) | **$0.10** (GPT-4.1 Nano) |
| 最高 Input | $5.00 (Opus) | $2.00 (3.1 Pro) | $0.435 (V4-Pro) | $5.00 (GPT-5.5) |
| 缓存读折扣 | 90% off | 90% off | **98% off** | 75%~90% off |
| 缓存写溢价 | **1.25x / 2x** | 无（+存储费） | **无** | 无 |
| 缓存机制 | 显式 `cache_control` | 显式 context caching | 自动 KV cache | 自动 prompt caching |

---

## 通用计费计算策略（基于 OpenCode 数据存储格式）

> 以下公式基于 OpenCode SQLite 数据库中 `$.tokens` 的字段含义（与源码 `getUsage()` 一致）：

```
// 各 token 类型独立计费，各自乘以显式 Provider profile 的对应单价
费用 = netInput × inputPrice + output × outputPrice + reasoning × reasoningPrice + billableCacheRead × cacheReadPrice + cacheWrite × cacheWritePrice

// 总成本 = 已启用固定订阅费用 + 未订阅部分 API 估算成本
// 若所有 Provider 订阅均关闭，总成本全部按 API 定价估算（各 Provider 独立判断）
```

## App 总计费口径（v0.6.x+）
// 各 token 类型独立计费，各自乘以对应单价
费用 = input × inputPrice
     + output × outputPrice
     + reasoning × reasoningPrice（通常等同 outputPrice）
     + cacheRead × cacheReadPrice（通常为 inputPrice 的 10%）
     + cacheWrite × cacheWritePrice（仅 Anthropic 溢价 125%~200%）

// Token Cost App 仪表盘实际 token 计算
// 注：OpenCode SQLite 中 input 字段已是非缓存值，此处不做 cache 减法。
// Codex 数据管线则通过 CodexTokenUsage.actualInputTokens（max(inputTokens - cachedInputTokens, 0)）计算。
actualInputTokens(OpenCode) = input
actualInputTokens(Codex) = max(inputTokens - cachedInputTokens, 0)
actualTokens = input + output + reasoning
totalTokens = actualTokens + cacheRead + cacheWrite
// 聚合命中率：分母 = 实际输入 + 展示缓存读（不含 output，避免高输出稀释命中率）
// displayedCacheRead = 真实 cacheRead + Ollama 估算 cacheRead（含估算时）
// Ollama gross input 先扣除估算部分，再计入展示缓存读
cacheHitRate = displayedCacheRead / (displayInputTotal + displayedCacheRead)

### 缓存节省费用（cacheSavedCost）

仅用于有 `inputPrice` 和 `cacheReadPrice` 双定价的模型。基于**真实** `cacheRead` 计算，不受估算值影响：

```
cacheSavedCost = cacheRead × (inputPrice − cacheReadPrice) / 1 000 000
```

当 `inputPrice ≤ cacheReadPrice` 或任一价格缺失时返回 0。该值计入缓存区 `cacheSavedCost` 指标卡片。

### Ollama Cloud 缓存读估算（展示口径）

当 `ollama-cloud` Provider 下 `cacheRead == 0` 且 `input > 0` 时，对 `deepseek-v4-flash` 和 `deepseek-v4-pro` 启用估算：

```
rate = runtimeRate ?? snapshot_cacheRead / snapshot_grossInput
estimatedCacheRead = ollamaGrossInput × rate
displayInput = input − estimatedCacheRead
displayedCacheRead = realCacheRead + estimatedCacheRead
displayedCacheHitRate = displayedCacheRead / (displayInput + displayedCacheRead)
```

估算值影响缓存展示、净实际 Token、Provider/模型 API 等值成本、tokens/$ 排行和 Relay `cost`；不写入源数据，不改变 gross `actualTokens`、订阅覆盖、raw db cost 或 `cacheSavedCost`。模型比较按 `(provider, model)` 拆分，同名模型不会跨 Provider 混价。
