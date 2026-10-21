#!/usr/bin/env python3
"""Compare legacy hard-coded token pricing with the auto-discovered catalog.

Reads the real OpenCode database plus OpenCode's models.dev cache and reports,
per provider and per model, how much the API-equivalent cost moves once model
ranking prices come from the catalog instead of `zenPricing` / `deepSeekLegacyPricing`.

The legacy tables are parsed out of DashboardAnalytics.swift so this report cannot
silently drift from the shipped snapshot.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sqlite3
import sys
from dataclasses import dataclass

DEFAULT_DB = os.path.expanduser("~/.local/share/opencode/opencode.db")
DEFAULT_CACHE = os.path.expanduser("~/.cache/opencode/models.json")
SWIFT_SOURCE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Sources/CodexTokenCostCore/DashboardAnalytics.swift",
)

ALIASES = {
    "minimax-m2.7-highspeed": "minimax-m2.7",
    "deepseek-chat": "deepseek-v4-flash",
    "deepseek-reasoner": "deepseek-v4-pro",
}
BUILD_QUALIFIERS = ("-cloud", "-fast", "-preview", "-latest", "-edge", "-thinking")
DATE_SUFFIX = re.compile(r"-\d{4,8}$")
TAG_SUFFIX = re.compile(r":[a-z0-9._]{1,24}$")


@dataclass
class Resolution:
    canonical: str
    matched: str | None
    match: str
    price: dict | None


def normalize_model(value: str) -> str:
    value = "-".join(value.lower().split())
    if "/" in value:
        value = value.rsplit("/", 1)[-1]
    return value


def strip_suffix(value: str):
    if ":" in value:
        candidate = value
        token = candidate[candidate.rfind(":") + 1:]
        if TAG_SUFFIX.fullmatch(":" + token) and value[: candidate.rfind(":")]:
            return value[: candidate.rfind(":")], ":" + token
    for suffix in BUILD_QUALIFIERS:
        if value.endswith(suffix) and len(value) > len(suffix):
            return value[: -len(suffix)], suffix
    match = DATE_SUFFIX.search(value)
    if match and match.start() > 0:
        return value[: match.start()], match.group(0)
    return None


def split_variants(value: str):
    tags, keys = [], []
    while True:
        stripped = strip_suffix(value)
        if not stripped:
            break
        value, tag = stripped
        tags.append(tag)
        keys.append(value)
    return value, tags, keys


def resolve(costs, provider: str, model: str) -> Resolution:
    provider = provider.lower().strip()
    raw = normalize_model(model)
    family, _tags, keys = split_variants(raw)
    table = costs.get(provider, {})
    free_named = raw.endswith("free")

    if raw in table:
        return Resolution(family, raw, "exact", table[raw])
    alias = ALIASES.get(raw)
    if alias and alias in table:
        return Resolution(split_variants(alias)[0], alias, "alias", table[alias])
    if free_named:
        return Resolution(family, None, "freeInferred", None)
    for key in keys:
        if key in table:
            return Resolution(family, key, "variant", table[key])
    if family in table:
        return Resolution(family, family, "family", table[family])
    for key in sorted(table, key=len, reverse=True):
        if raw.startswith(key) and len(raw) > len(key):
            return Resolution(family, key, "prefix", table[key])
    unique = [p for p, t in costs.items() if p != provider and family in t]
    if len(unique) == 1:
        return Resolution(family, family, "crossProvider", costs[unique[0]][family])
    return Resolution(family, None, "unknown", None)


def load_legacy_tables(path: str):
    source = open(path, encoding="utf-8").read()

    def parse(name: str):
        match = re.search(rf"private static let {name}: \[String: \[String: Double\]\] = \[(.*?)\n    \]", source, re.S)
        if not match:
            raise SystemExit(f"cannot find {name} in {path}")
        rows = {}
        for key, body in re.findall(r'"([^"]+)": \[([^\]]*)\]', match.group(1)):
            rows[key] = {}
            for field, value in re.findall(r'"(\w+)": ([0-9.]+)', body):
                rows[key][field] = float(value)
        return rows

    zen = parse("zenPricing")
    legacy = parse("deepSeekLegacyPricing")
    tables = {
        "opencode": zen,
        "opencode-go": zen,
        "ollama-cloud": zen,
        "deepseek": legacy,
        "deepseek-api-cn": legacy,
    }
    return tables


def legacy_price(tables, provider: str, model: str):
    key = normalize_model(model)
    if key in ALIASES:
        key = ALIASES[key]
    else:
        for base in sorted(zen_keys(tables), key=len, reverse=True):
            if key.startswith(base) and len(key) > len(base):
                key = base
                break
    return tables.get(provider.lower(), {}).get(key)


def zen_keys(tables):
    return set(tables.get("opencode", {}))


def cost(price: dict, input_t, output_t, reasoning_t, cache_read, cache_write) -> float:
    if not price:
        return 0.0
    output_price = price.get("out", price.get("output", 0.0))
    reasoning_price = price.get("reasoning", output_price)
    return (
        input_t * price.get("in", price.get("input", 0.0))
        + output_t * output_price
        + reasoning_t * reasoning_price
        + cache_read * price.get("cr", price.get("cacheRead", 0.0))
        + cache_write * price.get("cw", price.get("cacheWrite", 0.0))
    ) / 1_000_000


def load_catalog(path: str):
    raw = json.load(open(path, encoding="utf-8"))
    providers = raw.get("providers", raw)
    costs = {}
    for provider, value in providers.items():
        models = (value or {}).get("models") or {}
        table = {}
        for model, entry in models.items():
            c = (entry or {}).get("cost") or {}
            table[model.lower()] = {
                "in": c.get("input", 0.0),
                "out": c.get("output", 0.0),
                "cr": c.get("cache_read", 0.0),
                "cw": c.get("cache_write", 0.0),
            }
        if table:
            costs[provider.lower()] = table
    return costs


def load_rows(db_path: str, days: int):
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    v2 = f"""
        SELECT json_extract(data,'$.model.providerID') AS provider,
               json_extract(data,'$.model.id') AS model,
               json_extract(data,'$.tokens.input') AS input,
               json_extract(data,'$.tokens.output') AS output,
               json_extract(data,'$.tokens.reasoning') AS reasoning,
               json_extract(data,'$.tokens.cache.read') AS cache_read,
               json_extract(data,'$.tokens.cache.write') AS cache_write
        FROM session_message
        WHERE json_extract(data,'$.tokens') IS NOT NULL
          AND json_extract(data,'$.time.created') >= ?
    """
    legacy = f"""
        SELECT json_extract(data,'$.providerID') AS provider,
               json_extract(data,'$.modelID') AS model,
               json_extract(data,'$.tokens.input') AS input,
               json_extract(data,'$.tokens.output') AS output,
               json_extract(data,'$.tokens.reasoning') AS reasoning,
               json_extract(data,'$.tokens.cache.read') AS cache_read,
               json_extract(data,'$.tokens.cache.write') AS cache_write
        FROM message
        WHERE json_extract(data,'$.tokens') IS NOT NULL
          AND time_created >= ?
    """
    threshold = 0
    if days:
        import time

        threshold = int((time.time() - days * 86400) * 1000)
    rows = []
    for query in (v2, legacy):
        for provider, model, i, o, r, cr, cw in con.execute(query, (threshold,)):
            if not model:
                continue
            rows.append(
                (
                    (provider or "unknown").lower(),
                    model,
                    float(i or 0),
                    float(o or 0),
                    float(r or 0),
                    float(cr or 0),
                    float(cw or 0),
                )
            )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=DEFAULT_DB)
    parser.add_argument("--cache", default=DEFAULT_CACHE)
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    tables = load_legacy_tables(SWIFT_SOURCE)
    costs = load_catalog(args.cache)
    rows = load_rows(args.db, args.days)

    provider_totals = collections.defaultdict(lambda: [0.0, 0.0, 0])
    model_rows = collections.defaultdict(lambda: {"rows": 0, "old": 0.0, "new": 0.0, "match": "", "tokens": 0.0})
    kinds = collections.Counter()

    for provider, model, i, o, r, cr, cw in rows:
        old = cost(legacy_price(tables, provider, model), i, o, r, cr, cw)
        res = resolve(costs, provider, model)
        new = cost(res.price, i, o, r, cr, cw)
        kinds[res.match] += 1
        entry = provider_totals[provider]
        entry[0] += old
        entry[1] += new
        entry[2] += 1
        key = (provider, res.canonical)
        m = model_rows[key]
        m["rows"] += 1
        m["old"] += old
        m["new"] += new
        m["match"] = res.match
        m["tokens"] += i + o + r

    old_total = sum(v[0] for v in provider_totals.values())
    new_total = sum(v[1] for v in provider_totals.values())

    if args.json:
        print(json.dumps({
            "oldTotal": old_total,
            "newTotal": new_total,
            "kinds": kinds,
            "providers": provider_totals,
        }, indent=2))
        return 0

    print(f"窗口：最近 {args.days} 天 · 用量行 {len(rows):,}")
    print(f"旧口径合计：${old_total:,.2f}    目录口径合计：${new_total:,.2f}    "
          f"差额：{new_total - old_total:+,.2f}")
    print()
    print("解析命中（按行）：")
    for kind, count in kinds.most_common():
        print(f"  {kind:14s} {count:8,d}")
    print()
    print("按 Provider：")
    print(f"  {'provider':16s} {'rows':>8s} {'old $':>10s} {'new $':>10s} {'delta':>10s}")
    for provider, (old, new, count) in sorted(provider_totals.items(), key=lambda kv: -kv[1][0]):
        print(f"  {provider:16s} {count:8,d} {old:10.2f} {new:10.2f} {new - old:+10.2f}")
    print()
    print("变化最大的模型：")
    print(f"  {'provider':13s} {'model':34s} {'rows':>6s} {'old $':>9s} {'new $':>9s} {'match':>12s}")
    for (provider, model), m in sorted(model_rows.items(), key=lambda kv: -(kv[1]["new"] - kv[1]["old"]))[:15]:
        print(f"  {provider:13s} {model:34s} {m['rows']:6d} {m['old']:9.2f} {m['new']:9.2f} {m['match']:>12s}")
    print()
    unpriced = [(k, v) for k, v in model_rows.items() if v["match"] == "unknown"]
    print(f"仍未定价的模型：{len(unpriced)} 个 / {sum(v['rows'] for _, v in unpriced):,} 行")
    for (provider, model), m in sorted(unpriced, key=lambda kv: -kv[1]["tokens"])[:10]:
        print(f"  {provider:13s} {model:34s} rows={m['rows']:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
