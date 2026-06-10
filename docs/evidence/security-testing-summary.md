# Security Testing Evidence Summary

This document maps the AIEM security evaluation scenarios to the sanitized Postman collection included in this repository.

Postman files:

```text
postman/aiem-security-tests.postman_collection.json
postman/aiem.postman_environment.example.json
```

The collection does not include raw JWTs, passwords, client secrets, or environment-specific tokens. JWT attack tokens and scenario tokens must be generated locally and assigned to the corresponding Postman environment variables.

## JWT Attack Vectors

| ID | Postman Request | Token Variable | Expected Result | Actual Result |
|---|---|---|---|---|
| J1 | `01. JWT Attacks/J1. Algorithm None Attack` | `{{j1_alg_none_token}}` | Rejected at gateway | 401 Unauthorized |
| J2 | `01. JWT Attacks/J2. RS256 to HS256 Confusion` | `{{j2_alg_confusion_token}}` | Rejected at gateway | 401 Unauthorized |
| J3 | `01. JWT Attacks/J3. Claim Tampering` | `{{j3_claim_tampered_token}}` | Rejected at gateway | 401 Unauthorized |
| J4 | `01. JWT Attacks/J4. Expired Token Replay Attack` | `{{j4_expired_token}}` | Rejected at gateway | 401 Unauthorized |
| J5 | `01. JWT Attacks/J5. Invalid Signature` | `{{j5_invalid_signature_token}}` | Rejected at gateway | 401 Unauthorized |
| J6 | `01. JWT Attacks/J6. Audience Mismatch` | `{{j6_audience_mismatch_token}}` | Rejected by Service B inline PDP | 403 Forbidden |
| J7 | `01. JWT Attacks/J7. azp Mismatch` | `{{j7_azp_mismatch_token}}` | Rejected by Service B inline PDP | 403 Forbidden |
| J8 | `01. JWT Attacks/J8. Insufficient Scope` | `{{j8_insufficient_scope_token}}` | Rejected by Service B scope enforcement | 403 Forbidden |

## End-to-End Security Scenarios

| ID | Postman Request | Token Variable | Expected Result | Actual Result |
|---|---|---|---|---|
| S1 | `02. Security Scenarios/S1. SSRF Lateral Movement Baseline` | `{{user_token}}` | Baseline internal fetch reaches Service B internal endpoint | 200 OK |
| S2 | `02. Security Scenarios/S2. Defense-in-Depth: User Token to Service B` | `{{user_token}}` | User token rejected by Service B secure endpoint | 403 Forbidden |
| S3a | `02. Security Scenarios/S3a. M2M BOLA Prevention - Executive` | `{{user_token}}` | Executive data access blocked by scope enforcement | 403 Forbidden |
| S3b | `02. Security Scenarios/S3b. M2M BOLA - Staff` | `{{user_token}}` | Staff data request succeeds with masked response | 200 OK |
| S4a | `02. Security Scenarios/S4a. Token Type: User Token to Public Endpoint` | `{{user_token}}` | Public endpoint accepts user token | 200 OK |
| S4b | `02. Security Scenarios/S4b. Token Type: M2M Token to Public Endpoint` | `{{m2m_token}}` | Public endpoint rejects M2M token | 403 Forbidden |
| S5a | `02. Security Scenarios/S5a. Legacy BOLA` | `{{user_token}}` | Legacy baseline exposes unauthorized object access | 200 OK |
| S5b | `02. Security Scenarios/S5b. Secure Service B` | `{{m2m_token}}` | Secure Service B blocks executive data access | 403 Forbidden |
| S6 | `02. Security Scenarios/S6. No Token` | none | Gateway rejects request without token | 401 Unauthorized |
| S6b | `02. Security Scenarios/S6b. Fake Token` | `{{fake_token}}` | Gateway rejects fake token | 401 Unauthorized |
| S7a | `02. Security Scenarios/S7a. Steal CLIENT_SECRET` | `{{user_token}}` | Simulated exposure endpoint is disabled by default | 403 Forbidden by default |
| S7b | `02. Security Scenarios/S7b. Create Token with Stolen Credential` | `{{client_secret_m2m}}` | A valid M2M token can be created when the client secret is stolen | 200 OK |
| S7c | `02. Security Scenarios/S7c. Access Staff with Stolen Token` | `{{stolen_token}}` | Staff data can be accessed using a valid stolen M2M token | 200 OK |
| S7d | `02. Security Scenarios/S7d. Access Executive with Stolen Token` | `{{stolen_token}}` | Executive data remains blocked by scope enforcement | 403 Forbidden |

## Token Handling Notes

Raw JWT values are intentionally excluded from this repository.

The following values must be generated locally before running the corresponding requests:

```text
user_token
m2m_token
stolen_token
j1_alg_none_token
j2_alg_confusion_token
j3_claim_tampered_token
j4_expired_token
j5_invalid_signature_token
j6_audience_mismatch_token
j7_azp_mismatch_token
j8_insufficient_scope_token
```

This prevents the artifact from exposing environment-specific JWTs, client secrets, or test credentials.
