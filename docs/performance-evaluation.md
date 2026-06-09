# Performance Evaluation

This document summarizes the performance evaluation supported by this artifact.

The performance test uses k6 to compare baseline and AIEM request paths.

## Test Conditions

| Condition | Name | Description |
|---|---|---|
| A | Baseline | Request path without M2M enforcement overhead |
| B | AIEM cold cache | AIEM path with token/JWKS cache initially empty |
| C | AIEM warm cache | AIEM path after token/JWKS cache is populated |

## k6 Test Files

| File | Purpose |
|---|---|
| `k6-tests/test_A_baseline.js` | Runs condition A |
| `k6-tests/test_B_cold.js` | Runs condition B |
| `k6-tests/test_C_warm.js` | Runs condition C |
| `k6-tests/run_all.sh` | Runs repeated evaluation sequence |

## Required Environment Variables

Before running k6, load the local environment file:

```bash
source .env
```

Required variables:

```text
SERVICE_A_CLIENT_SECRET
K6_TEST_USERNAME
K6_TEST_PASSWORD
KONG_PROXY_URL
KEYCLOAK_TOKEN_URL
```

## Run All Tests

```bash
./k6-tests/run_all.sh
```

The script runs repeated measurements for conditions A, B, and C.

## Output Location

Generated k6 JSON outputs are written to:

```text
performance/results/
```

The generated JSON files are ignored by Git because they can be large.

## Cache Behavior

Condition B disables the M2M token cache and restarts relevant services to force cold-cache behavior. Condition C restores the normal Service A container so repeated requests use the warm-cache path.

## Interpretation

The performance result should be interpreted as local prototype behavior under the VM and test configuration used in the study. The result is not a general benchmark for Kong, Keycloak, Flask, or all microservice deployments.
