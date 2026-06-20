# Performance Evaluation

This document explains how to reproduce the performance evaluation supported by this artifact.

The performance tests use k6 to compare three service-to-service request conditions through the same default target path: `/api/a/api/fetch-employee-secure/1`.

Using the same target path avoids comparing different endpoint paths and makes the baseline and AIEM warm-cache condition more directly comparable.

## Test Conditions

| Condition | Name | Description |
|---|---|---|
| A | Same-path baseline | Service A calls Service B through the same secure path, but Service B resource-level PDP validation is disabled with `AIEM_PDP_MODE=off`. Service A uses its normal M2M token cache. |
| B | AIEM cold cache | Service B PDP validation is enabled, Service B is recreated to reset its in-memory JWKS cache, and Service A is recreated with `DISABLE_M2M_CACHE=true` so each request obtains a fresh M2M token. |
| C | AIEM warm cache | Service B PDP validation is enabled, Service A uses its normal M2M token cache, and the target path is warmed before measurement to populate Service A token cache and Service B JWKS cache. |

Condition A is not the legacy-service baseline. It is a same-path baseline designed to isolate the additional resource-level authorization cost of AIEM while keeping the Service A to Service B request path comparable with Condition C.

## Performance Test Files

| File | Purpose |
|---|---|
| `k6-tests/performance_test.js` | Parameterized k6 script used by all measured conditions |
| `k6-tests/run_all.sh` | Orchestrates mode switching, warmup, counterbalanced execution order, JSON output, rate-limit handling, and cleanup |
| `scripts/set-performance-mode.sh` | Applies `baseline`, `aiem-cold`, `aiem-warm`, or `restore` runtime modes |

The previous condition-specific k6 scripts were removed because they used different request paths and could produce non-apple-to-apple comparisons.

## Prerequisites

Before running the performance tests: start the Docker Compose stack, run `scripts/setup-keycloak.sh`, run `scripts/setup-kong.sh`, and ensure k6 is installed.

The runner automatically loads the repository `.env` file. Required variables include `SERVICE_A_CLIENT_SECRET`, `K6_TEST_USERNAME`, `K6_TEST_PASSWORD`, `KONG_PROXY_URL`, and `KEYCLOAK_TOKEN_URL`.

## Full Evaluation

Run `./k6-tests/run_all.sh`.

By default, the runner uses one repetition of the counterbalanced order plan: `ABC,ACB,BAC,BCA,CAB,CBA`.

Each block runs the three conditions in the specified order. This reduces fixed-order bias compared with always executing A, then B, then C.

Useful overrides:

| Variable | Default |
|---|---|
| `REPETITIONS` | `1` |
| `ORDER_PLAN` | `ABC,ACB,BAC,BCA,CAB,CBA` |
| `COOLDOWN_SECONDS` | `120` |
| `WARMUP_SECONDS` | `20` |
| `WARMUP_REQUESTS` | `20` |
| `K6_RAMP_UP` | `30s` |
| `K6_STEADY` | `90s` |
| `K6_RAMP_DOWN` | `30s` |
| `K6_MAX_VUS` | `10` |
| `K6_SLEEP_SECONDS` | `0.5` |

## Smoke Test

To validate the orchestration without running the full sequence:

    REPETITIONS=1 \
    ORDER_PLAN=ABC \
    COOLDOWN_SECONDS=0 \
    WARMUP_SECONDS=2 \
    WARMUP_REQUESTS=3 \
    K6_RAMP_UP=1s \
    K6_STEADY=3s \
    K6_RAMP_DOWN=1s \
    K6_MAX_VUS=1 \
    K6_SLEEP_SECONDS=0.2 \
    ./k6-tests/run_all.sh

The smoke test validates the workflow but should not replace repeated measurements used for reporting performance results.

## Output Location

Generated JSON outputs are written to `performance/results/`.

The filenames follow this pattern: `k6_<condition>_rep<repetition>_block<block>_pos<position>.json`.

Examples: `k6_A_rep1_block1_pos1.json`, `k6_B_rep1_block1_pos2.json`, and `k6_C_rep1_block1_pos3.json`.

These generated files are ignored by Git because they can be large.

## Metrics to Use

Use the custom latency metrics for reporting condition latency:

- `condA_baseline_same_path_latency_ms`
- `condB_aiem_cold_cache_latency_ms`
- `condC_aiem_warm_cache_latency_ms`

Do not use `http_req_duration` as the primary reported latency metric, because it also includes the setup token request made by k6. The custom latency metrics measure only the target endpoint request.

## Rate-Limit and Cleanup

During performance testing, the runner temporarily raises the Kong rate limit to avoid HTTP 429 responses contaminating latency measurements. After completion, interruption, or failure, the runner restores the normal artifact state: Service B PDP ON, Service A token cache ON, and Kong rate limit restored to normal.

## Interpretation

The measurements represent local prototype behavior under the VM, container state, host load, and test configuration used during each run. Absolute latency may differ between reproduction runs. Comparative behavior and repeated-run statistics should be evaluated instead of treating one smoke run as a replacement for the study dataset.
