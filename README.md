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

## Environment Setup

Copy the example environment file:

```bash
cp .env.example .env
```

Then edit `.env` and replace placeholder values with local lab values.

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

After Keycloak is ready, configure Kong:

```bash
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

Run the k6 test set:

```bash
source .env
./k6-tests/run_all.sh
```

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
