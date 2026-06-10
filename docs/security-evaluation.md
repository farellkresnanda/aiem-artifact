# Security Evaluation

This document summarizes the security evaluation supported by this artifact.

The evaluation focuses on the difference between gateway-only validation and dual-layer AIEM validation. Kong performs gateway-level JWT validation, while Service B performs resource-level authorization validation using an inline PDP.

## Enforcement Layers

| Layer | Component | Responsibility |
|---|---|---|
| Gateway layer | Kong Gateway | Validates JWT authenticity and basic validity |
| Resource layer | Service B inline PDP | Validates application identity and authorization claims |

## Minimum Viable Claims Set

AIEM uses a Minimum Viable Claims Set (MVCS) to separate gateway-level and resource-level validation.

| Claim / Element | Validation Layer | Purpose |
|---|---|---|
| `iss` | Gateway | Confirms trusted token issuer |
| `exp` | Gateway | Rejects expired tokens |
| `alg` | Gateway | Enforces expected signing algorithm |
| `aud` | Service B | Confirms token is intended for Service B |
| `azp` | Service B | Confirms the authorized calling application |
| `scope` | Service B | Confirms the requested privilege is allowed |

## JWT Attack Vectors

| ID | Vector | Expected Result |
|---|---|---|
| J1 | Algorithm `none` | Rejected at gateway |
| J2 | RS256 to HS256 confusion | Rejected at gateway |
| J3 | Claim tampering | Rejected at gateway |
| J4 | Expired token replay | Rejected at gateway |
| J5 | Invalid signature | Rejected at gateway |
| J6 | Audience mismatch | Rejected by Service B inline PDP |
| J7 | Authorized party (`azp`) mismatch | Rejected by Service B inline PDP |
| J8 | Insufficient or escalated scope | Rejected by Service B scope enforcement |

## End-to-End Attack Scenarios

| ID | Scenario | AIEM State | Expected Result |
|---|---|---|---|
| S1 | SSRF lateral movement baseline | OFF | Not mitigated |
| S2 | User token sent to Service B secure endpoint | ON | Rejected by Service B |
| S3 | M2M BOLA attempt against executive data | ON | Rejected by Service B |
| S4 | Token type enforcement at public endpoint | ON | User token allowed, M2M token rejected |
| S5 | Gateway-only BOLA baseline | OFF | Not mitigated |
| S6 | No token or invalid token | ON | Rejected at gateway |
| S7 | Stolen client secret obtains valid M2M token | ON | Not mitigated |

## Important Safety Note

Some endpoints are included as controlled baseline or simulation endpoints to reproduce the evaluated research scenarios.

The simulated credential exposure endpoint in Service A is disabled by default. Enable it only when reproducing S7:

```text
ENABLE_SIMULATED_SECRET_LEAK=true
```

Do not expose this artifact directly to a public network.

## Interpretation Boundary

This artifact evaluates AIEM within a controlled local prototype. The results should not be interpreted as a full production Zero Trust deployment.
