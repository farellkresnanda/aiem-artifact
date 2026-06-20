#!/usr/bin/env python3
import csv
import json
import math
import re
import statistics
from pathlib import Path

RESULT_DIR = Path("performance/results")

LATENCY_METRICS = {
    "A": "condA_baseline_same_path_latency_ms",
    "B": "condB_aiem_cold_cache_latency_ms",
    "C": "condC_aiem_warm_cache_latency_ms",
}

CONDITION_NAMES = {
    "A": "Same-path baseline",
    "B": "AIEM cold cache",
    "C": "AIEM warm cache",
}

def percentile(values, p):
    values = sorted(values)
    if not values:
        return None
    if len(values) == 1:
        return values[0]
    k = (len(values) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return values[int(k)]
    return values[f] + (values[c] - values[f]) * (k - f)

def summarize(values):
    return {
        "n": len(values),
        "avg": sum(values) / len(values),
        "min": min(values),
        "med": percentile(values, 50),
        "p90": percentile(values, 90),
        "p95": percentile(values, 95),
        "p99": percentile(values, 99),
        "max": max(values),
    }

def fmt(x):
    if x is None:
        return ""
    return f"{x:.2f}"

run_rows = []
pooled_values = {k: [] for k in LATENCY_METRICS}
pooled_errors = {k: [] for k in LATENCY_METRICS}

for path in sorted(RESULT_DIR.glob("k6_*.json")):
    m = re.match(r"k6_([ABC])_rep(\d+)_block(\d+)_pos(\d+)\.json$", path.name)
    if not m:
        continue

    condition, repetition, block, position = m.groups()
    latency_metric = LATENCY_METRICS[condition]
    error_metric = latency_metric.replace("latency_ms", "error_rate")

    latencies = []
    errors = []

    with path.open("r", encoding="utf-8") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            if obj.get("type") != "Point":
                continue

            metric = obj.get("metric")
            value = obj.get("data", {}).get("value")

            if not isinstance(value, (int, float)):
                continue

            if metric == latency_metric:
                latencies.append(float(value))
            elif metric == error_metric:
                errors.append(float(value))

    if not latencies:
        raise SystemExit(f"No latency samples found in {path}")

    s = summarize(latencies)
    error_rate = (sum(errors) / len(errors)) if errors else 0.0

    pooled_values[condition].extend(latencies)
    pooled_errors[condition].extend(errors)

    run_rows.append({
        "condition": condition,
        "name": CONDITION_NAMES[condition],
        "repetition": int(repetition),
        "block": int(block),
        "position": int(position),
        "file": path.name,
        "error_rate": error_rate,
        **s,
    })

summary_rows = []
baseline_avg = summarize(pooled_values["A"])["avg"]

for condition in ["A", "B", "C"]:
    pooled = summarize(pooled_values[condition])
    runs = [r for r in run_rows if r["condition"] == condition]
    run_avgs = [r["avg"] for r in runs]
    run_p95s = [r["p95"] for r in runs]
    run_p99s = [r["p99"] for r in runs]
    errors = pooled_errors[condition]
    error_rate = (sum(errors) / len(errors)) if errors else 0.0

    summary_rows.append({
        "condition": condition,
        "name": CONDITION_NAMES[condition],
        "runs": len(runs),
        "n": pooled["n"],
        "avg": pooled["avg"],
        "p95": pooled["p95"],
        "p99": pooled["p99"],
        "min": pooled["min"],
        "max": pooled["max"],
        "error_rate": error_rate,
        "mean_run_avg": statistics.mean(run_avgs),
        "sd_run_avg": statistics.stdev(run_avgs) if len(run_avgs) > 1 else 0.0,
        "mean_run_p95": statistics.mean(run_p95s),
        "sd_run_p95": statistics.stdev(run_p95s) if len(run_p95s) > 1 else 0.0,
        "mean_run_p99": statistics.mean(run_p99s),
        "sd_run_p99": statistics.stdev(run_p99s) if len(run_p99s) > 1 else 0.0,
        "avg_delta_vs_A_ms": pooled["avg"] - baseline_avg,
        "avg_delta_vs_A_pct": ((pooled["avg"] - baseline_avg) / baseline_avg) * 100.0,
    })

run_csv = RESULT_DIR / "per-run-summary.csv"
summary_csv = RESULT_DIR / "condition-summary.csv"
summary_md = RESULT_DIR / "performance-summary.md"

with run_csv.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(run_rows[0].keys()))
    writer.writeheader()
    writer.writerows(run_rows)

with summary_csv.open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=list(summary_rows[0].keys()))
    writer.writeheader()
    writer.writerows(summary_rows)

lines = []
lines.append("# Performance Summary")
lines.append("")
lines.append("| Condition | Name | Runs | Samples | Avg (ms) | p95 (ms) | p99 (ms) | Error rate | Avg delta vs A |")
lines.append("|---|---|---:|---:|---:|---:|---:|---:|---:|")
for r in summary_rows:
    lines.append(
        f"| {r['condition']} | {r['name']} | {r['runs']} | {r['n']} | "
        f"{fmt(r['avg'])} | {fmt(r['p95'])} | {fmt(r['p99'])} | "
        f"{r['error_rate']:.2%} | {fmt(r['avg_delta_vs_A_ms'])} ms ({r['avg_delta_vs_A_pct']:.2f}%) |"
    )

lines.append("")
lines.append("## Per-run stability")
lines.append("")
lines.append("| Condition | Mean run avg (ms) | SD run avg | Mean run p95 (ms) | SD run p95 | Mean run p99 (ms) | SD run p99 |")
lines.append("|---|---:|---:|---:|---:|---:|---:|")
for r in summary_rows:
    lines.append(
        f"| {r['condition']} | {fmt(r['mean_run_avg'])} | {fmt(r['sd_run_avg'])} | "
        f"{fmt(r['mean_run_p95'])} | {fmt(r['sd_run_p95'])} | "
        f"{fmt(r['mean_run_p99'])} | {fmt(r['sd_run_p99'])} |"
    )

summary_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

print("\n".join(lines))
print()
print(f"Wrote: {run_csv}")
print(f"Wrote: {summary_csv}")
print(f"Wrote: {summary_md}")
