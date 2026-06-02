# Provider 计费与订阅档位速查

> 本文档为 App 内置只读参考。实际价格可能变更，设置页提供「自定义 USD 月费」作为兜底。
> 总成本 = 已启用固定订阅费用 + 未订阅部分 API 估算成本；若所有订阅关闭，总成本全部按 API 定价估算。

## OpenCode

| 档位 | 费用 | 说明 |
|---|---:|---|
| OpenCode Go | $10/月 | 官方低成本 coding models 订阅；首月 $5 是促销，不作为默认长期月费。 |
| OpenCode Zen | 按量计费 | 透明 token/request 计费，无固定月费。 |

## ChatGPT / Codex

| 档位 | 费用 | 说明 |
|---|---:|---|
| ChatGPT Plus | $20/月 | 当前总览页默认 Codex 订阅口径。 |
| ChatGPT Pro | $200/月 | 更高 Codex 使用量和 Pro 模型能力。 |
| Business Codex | 按量计费 | 开发团队按使用量付费，无固定 seat fee。 |

## MiniMax Token Plan

| 档位 | 月费 | 额度 |
|---|---:|---|
| Starter 标准版 | ¥29/月 | M2.7 600 次请求/5小时 |
| Plus 标准版 | ¥49/月 | M2.7 1,500 次请求/5小时 |
| Max 标准版 | ¥119/月 | M2.7 4,500 次请求/5小时 |
| Plus 极速版 | ¥98/月 | M2.7-highspeed 1,500 次请求/5小时 |
| Max 极速版 | ¥199/月 | M2.7-highspeed 4,500 次请求/5小时 |
| Ultra 极速版 | ¥899/月 | M2.7-highspeed 30,000 次请求/5小时 |

## Xiaomi MiMo Token Plan

| 档位 | 中国区月费 | 海外月费 | 海外年付 | Credits |
|---|---:|---:|---:|---:|
| Lite | ¥39/月 | $6/月 | $63.36/年 | 60M/月；720M/年 |
| Standard | ¥99/月 | $16/月 | $168.96/年 | 200M/月；2400M/年 |
| Pro | ¥329/月 | $50/月 | $528/年 | 700M/月；8400M/年 |
| Max | ¥659/月 | $100/月 | $1056/年 | 1600M/月；19200M/年 |

## MiMo Credits 消耗规则

| 模型 | Credit 消耗 |
|---|---|
| MiMo-V2.5 | 1 Token = 1 Credit |
| MiMo-V2.5-Pro | 1 Token = 2 Credits |
| MiMo-V2.5-TTS | 以平台当前页面为准 |

MiMo 套餐是 Credit 包，不是无限请求包；Agent 多轮工具调用会快速消耗额度，实际耐用程度取决于模型、上下文长度、工具调用次数和缓存命中。

## DeepSeek API

| 模型 | 输入 (缓存命中) | 输入 (缓存未命中) | 输出 |
|---|---:|---:|---:|
| V4-Flash | $0.0028/M | $0.14/M | $0.28/M |
| V4-Pro | $0.003625/M | $0.435/M | $0.87/M |

> V4-Pro 正式永久定价为原参考价 1/4（2026/06/01 起生效）。缓存写入无额外费用，自动 KV 缓存。
> deepseek-chat / deepseek-reasoner 将于 2026/07/24 弃用，当前兼容映射到 V4-Flash。
