# Reproduction Guide

This document explains how to reproduce the AIEM prototype locally.

## 1. Prepare Environment

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` and replace placeholder values with local values.

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

The export is sanitized and does not include client secrets or user credentials. Local client secrets and test users must be configured manually or regenerated in Keycloak.

## 4. Kong Configuration

After Keycloak is running, configure Kong:

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

Run the performance test set with:

```bash
source .env
./k6-tests/run_all.sh
```

Generated k6 JSON outputs are stored in:

```text
performance/results/
```
