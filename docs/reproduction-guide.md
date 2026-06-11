# Reproduction Guide

This document explains how to reproduce the AIEM prototype locally.

## 1. Prepare Environment

Copy the example environment file:

```bash
cp .env.example .env
```

The default values in `.env.example` are sufficient for local reproduction. You may change them, but keep `.env` and Keycloak aligned by rerunning `scripts/setup-keycloak.sh`.

Required variables:

```text
KEYCLOAK_ADMIN
KEYCLOAK_ADMIN_PASSWORD
KONG_PG_PASSWORD
SERVICE_A_CLIENT_SECRET
K6_TEST_USERNAME
K6_TEST_PASSWORD
```

Do not commit `.env`.

## 2. Start Containers

Build and start the stack:

```bash
docker compose --env-file .env up -d --build
```

Check container status:

```bash
docker ps
```

Expected core containers:

```text
keycloak
kong-db
kong
service-a
service-b
legacy-service
```

## 3. Keycloak Configuration

The sanitized Keycloak realm export is located at:

```text
configs/keycloak/realm-export-sanitized.json
```

The realm is imported automatically when Keycloak starts. The export is sanitized and does not include client secrets or user credentials.

After Keycloak is running, apply the local Service A client secret and test-user password from `.env`:

```bash
./scripts/setup-keycloak.sh
```

## 4. Kong Configuration

After Keycloak has been configured, configure Kong:

```bash
./scripts/setup-kong.sh
```

The script registers Kong services, routes, JWT validation, and rate limiting.

## 5. Security Evaluation

Security scenarios are documented in:

```text
docs/security-evaluation.md
```

## 6. Performance Evaluation

Performance tests are documented in:

```text
docs/performance-evaluation.md
```

Run the default five-run evaluation sequence:

```bash
./k6-tests/run_all.sh
```

The runner automatically loads `.env`, executes conditions A, B, and C, performs a 20-second warmup before each Condition C measurement, and waits 120 seconds between complete runs.

For a single-run orchestration smoke test without cooldown:

```bash
RUN_COUNT=1 COOLDOWN_SECONDS=0 ./k6-tests/run_all.sh
```

Generated k6 JSON outputs are stored in:

```text
performance/results/
```

The generated files are ignored by Git because they can be large.
