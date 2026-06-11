# Zero Trust-Aligned AIEM Research Artifact

This repository contains the implementation artifact for the paper:

**Implementation and Security Evaluation of a Zero Trust-Aligned Application-Identity Enforcement Model for API Gateway in Microservices Architecture**

The artifact implements an Application-Identity Enforcement Model (AIEM) for microservices service-to-service authorization. The system uses Keycloak as the identity provider, Kong Gateway as the gateway-level policy enforcement point, Service A as the entry-point service, Service B as the downstream highly sensitive service, and a legacy baseline service for comparison.

## Repository Structure

```text
.
├── docker-compose.yml
├── .env.example
├── configs/
│   └── keycloak/
│       └── realm-export-sanitized.json
├── scripts/
│   ├── setup-keycloak.sh
│   └── setup-kong.sh
├── services/
│   ├── service-a/
│   ├── service-b/
│   └── legacy-service/
├── k6-tests/
│   ├── run_all.sh
│   ├── test_A_baseline.js
│   ├── test_B_cold.js
│   └── test_C_warm.js
├── postman/
│   ├── aiem-security-tests.postman_collection.json
│   └── aiem.postman_environment.example.json
└── docs/
    ├── reproduction-guide.md
    ├── security-evaluation.md
    ├── performance-evaluation.md
    └── evidence/
        └── security-testing-summary.md
```

## Main Components

- Keycloak: OAuth2/OIDC identity provider and JWT issuer.
- Kong Gateway: gateway-level JWT validation and routing.
- Service A: entry-point service that obtains M2M tokens from Keycloak.
- Service B: downstream service with inline PDP validation for `aud`, `azp`, and `scope`.
- Legacy Service: brownfield baseline service that relies on gateway-level validation without resource-layer authorization checks.

## Requirements

- Docker
- Docker Compose
- curl
- jq
- k6
- Python 3
- Python cryptography package, for example `python3-cryptography` on Ubuntu

## Environment Setup

Copy the example environment file:

```bash
cp .env.example .env
```

The default values in `.env.example` are sufficient for local reproduction. The `scripts/setup-keycloak.sh` script applies the local Service A client secret and test-user password from `.env` to the imported Keycloak realm. You may change these values, but keep `.env` and Keycloak aligned by rerunning the setup script.

Important variables:

```text
KEYCLOAK_ADMIN
KEYCLOAK_ADMIN_PASSWORD
KONG_PG_PASSWORD
SERVICE_A_CLIENT_SECRET
K6_TEST_USERNAME
K6_TEST_PASSWORD
```

Do not commit `.env`.

## Running the Stack

```bash
docker compose --env-file .env up -d --build
```

After Keycloak is ready, apply the local Keycloak settings and configure Kong:

```bash
./scripts/setup-keycloak.sh
./scripts/setup-kong.sh
```

## Security Evaluation

Security evaluation documentation is available in:

```text
docs/security-evaluation.md
```

It covers JWT attack vectors J1-J8 and end-to-end scenarios S1-S7.

## Performance Evaluation

Performance evaluation documentation is available in:

```text
docs/performance-evaluation.md
```

Run the default evaluation sequence:

```bash
./k6-tests/run_all.sh
```

The script automatically loads `.env`, performs five runs for conditions A, B, and C, and waits 120 seconds between runs. Before each Condition C measurement, the runner primes the AIEM path and waits 20 seconds to warm the token and JWKS caches.

For a single-run orchestration smoke test without cooldown:

```bash
RUN_COUNT=1 COOLDOWN_SECONDS=0 ./k6-tests/run_all.sh
```

During performance testing, the script temporarily raises the Kong rate limit to prevent HTTP 429 responses from contaminating the latency measurements. On completion, interruption, or failure, it restores Service A to normal cached mode and returns the Kong rate limit to its default value.

Generated JSON outputs are stored under:

```text
performance/results/
```

Large generated JSON outputs are ignored by Git by default.

## Safety Notes

This artifact contains controlled baseline and simulation endpoints for research evaluation, including a brownfield legacy baseline and a disabled-by-default simulated credential exposure endpoint in Service A.

The simulated secret leak endpoint is disabled by default. It should only be enabled when reproducing scenario S7:

```text
ENABLE_SIMULATED_SECRET_LEAK=true
```

## Artifact Boundary

This artifact is designed for local reproduction of the evaluated prototype. It does not claim to provide a production-ready Zero Trust deployment.
