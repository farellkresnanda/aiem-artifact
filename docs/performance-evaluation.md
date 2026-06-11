# Performance Evaluation

This document explains how to reproduce the performance evaluation supported by this artifact.

The performance tests use k6 to compare the baseline request path with the AIEM cold-cache and warm-cache paths.

## Test Conditions

| Condition | Name | Description |
|---|---|---|
| A | Baseline | Request path without M2M token acquisition or resource-layer enforcement overhead |
| B | AIEM cold cache | Service A fetches a fresh M2M token for every request, while Service B is restarted before the test to clear its in-memory JWKS cache |
| C | AIEM warm cache | Service A uses its normal M2M token cache and Service B retains its initialized JWKS cache |

## k6 Test Files

| File | Purpose |
|---|---|
| `k6-tests/test_A_baseline.js` | Runs condition A |
| `k6-tests/test_B_cold.js` | Runs condition B |
| `k6-tests/test_C_warm.js` | Runs condition C |
| `k6-tests/run_all.sh` | Orchestrates repeated A, B, and C runs |

## Prerequisites

Before running the performance tests:

1. Start the Docker Compose stack.
2. Run `scripts/setup-keycloak.sh`.
3. Run `scripts/setup-kong.sh`.
4. Ensure k6 is installed.

The runner automatically loads the repository `.env` file.

Required variables include:

```text
SERVICE_A_CLIENT_SECRET
K6_TEST_USERNAME
K6_TEST_PASSWORD
KONG_PROXY_URL
KEYCLOAK_TOKEN_URL
```

## Full Evaluation

Run the default evaluation sequence:

```bash
./k6-tests/run_all.sh
```

By default, the runner performs five complete runs. Each run executes conditions A, B, and C, with a 120-second cooldown between consecutive runs.

The defaults can be overridden with environment variables:

```text
RUN_COUNT=5
COOLDOWN_SECONDS=120
WARMUP_SECONDS=20
```

## Single-Run Smoke Test

To validate the complete orchestration without running the full five-run sequence:

```bash
RUN_COUNT=1 COOLDOWN_SECONDS=0 ./k6-tests/run_all.sh
```

The smoke test validates the workflow but should not replace the repeated measurements used for the paper's reported results.

## Rate-Limit Handling

The normal artifact configuration uses a Kong rate limit of 120 requests per minute.

During performance testing, the runner temporarily raises the limit to 100000 requests per minute so that HTTP 429 responses do not contaminate latency measurements. The runner restores the original limit after completion, interruption, or failure.

The override can be changed through:

```text
PERFORMANCE_RATE_LIMIT_MINUTE=100000
KONG_RATE_LIMIT_MINUTE=120
```

## Service and Cache Handling

Before each condition, the runner prepares the required Service A mode and waits for actual HTTP readiness.

- Condition A restores the normal Service A container and uses the baseline endpoint.
- Condition B restarts Service B, disables the Service A M2M token cache, and uses the AIEM endpoint.
- Condition C restores the normal cached Service A container, primes the AIEM path to populate the Service A token cache and Service B JWKS cache, waits 20 seconds by default, and then starts the measurement.

After the sequence, Service A is returned to normal cached mode and Kong is returned to its normal rate-limit configuration.

## Output Location

Generated JSON outputs are written to:

```text
performance/results/
```

The filenames follow this pattern:

```text
k6_A_run<N>.json
k6_B_run<N>.json
k6_C_run<N>.json
```

These generated files are ignored by Git because they can be large.

## Interpretation

The measurements represent local prototype behavior under the VM, container state, host load, and test configuration used during each run. A reproduction run may differ in absolute latency from the paper's reported values. Comparative behavior and repeated-run statistics should be evaluated instead of treating one smoke run as a replacement for the study dataset.
