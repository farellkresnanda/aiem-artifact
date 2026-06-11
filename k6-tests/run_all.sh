#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
K6_DIR="$SCRIPT_DIR"

if [ -f "$COMPOSE_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$COMPOSE_DIR/.env"
    set +a
fi

command -v k6 >/dev/null 2>&1 || {
    echo "ERROR: k6 is required to run performance tests." >&2
    echo "Install k6 first, then rerun this script." >&2
    exit 1
}

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$COMPOSE_DIR")}"
NETWORK="${DOCKER_NETWORK:-${PROJECT_NAME}_zero-trust-net}"
IMAGE="${SERVICE_A_IMAGE:-${PROJECT_NAME}-service-a}"
RUN_COUNT="${RUN_COUNT:-5}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-120}"
WARMUP_SECONDS="${WARMUP_SECONDS:-20}"
PERFORMANCE_RATE_LIMIT_MINUTE="${PERFORMANCE_RATE_LIMIT_MINUTE:-100000}"
ORIGINAL_RATE_LIMIT_MINUTE="${KONG_RATE_LIMIT_MINUTE:-120}"

: "${SERVICE_A_CLIENT_SECRET:?SERVICE_A_CLIENT_SECRET environment variable is required}"
: "${K6_TEST_PASSWORD:?K6_TEST_PASSWORD environment variable is required}"

export KONG_PROXY_URL="${KONG_PROXY_URL:-http://localhost:8000}"
export KEYCLOAK_TOKEN_URL="${KEYCLOAK_TOKEN_URL:-http://localhost:8080/realms/zero-trust/protocol/openid-connect/token}"
export K6_TEST_USERNAME="${K6_TEST_USERNAME:-testuser}"

wait_for_oidc() {
    local discovery_url
    discovery_url="${KEYCLOAK_TOKEN_URL%/protocol/openid-connect/token}/.well-known/openid-configuration"

    echo "[WAIT] Waiting for Keycloak OIDC readiness..."
    until curl -fsS "$discovery_url" >/dev/null; do
        sleep 3
    done
    echo "[OK] Keycloak OIDC ready"
}

wait_for_container_health() {
    local container="$1"
    local status

    echo "[WAIT] Waiting for $container health..."
    while true; do
        status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || true)"

        if [ "$status" = "healthy" ] || [ "$status" = "running" ]; then
            echo "[OK] $container ready"
            return 0
        fi

        if [ "$status" = "unhealthy" ] || [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
            echo "ERROR: $container entered state: $status" >&2
            return 1
        fi

        sleep 2
    done
}

wait_for_service_a_http() {
    echo "[WAIT] Waiting for Service A HTTP readiness..."
    until docker exec service-a python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health', timeout=3)" >/dev/null 2>&1; do
        sleep 2
    done
    echo "[OK] Service A HTTP ready"
}

warm_up_aiem_path() {
    local token

    echo "[WARMUP] Priming AIEM token and JWKS caches..."

    token="$(
        curl -fsS -X POST "$KEYCLOAK_TOKEN_URL"             -H "Content-Type: application/x-www-form-urlencoded"             --data-urlencode "grant_type=password"             --data-urlencode "client_id=webapp-client"             --data-urlencode "username=$K6_TEST_USERNAME"             --data-urlencode "password=$K6_TEST_PASSWORD"         | jq -r '.access_token // empty'
    )"

    if [ -z "$token" ]; then
        echo "ERROR: failed to obtain user token for warmup" >&2
        return 1
    fi

    curl -fsS         -H "Authorization: Bearer $token"         "$KONG_PROXY_URL/api/a/api/fetch-employee-secure/1" >/dev/null

    if [ "$WARMUP_SECONDS" -gt 0 ]; then
        echo "[WARMUP] Waiting $WARMUP_SECONDS seconds..."
        sleep "$WARMUP_SECONDS"
    fi

    echo "[OK] AIEM path warmup completed"
}

run_service_a_normal() {
    docker stop service-a 2>/dev/null || true
    docker rm service-a 2>/dev/null || true
    cd "$COMPOSE_DIR" && docker compose --env-file "$COMPOSE_DIR/.env" up -d service-a
    wait_for_container_health service-a
    wait_for_service_a_http
    echo "[OK] service-a normal (cache ON)"
}

run_service_a_cold() {
    docker stop service-a 2>/dev/null || true
    docker rm service-a 2>/dev/null || true

    docker run -d \
        --name service-a \
        --network "$NETWORK" \
        -e DISABLE_M2M_CACHE=true \
        -e KEYCLOAK_TOKEN_URL=http://keycloak:8080/realms/zero-trust/protocol/openid-connect/token \
        -e CLIENT_ID=service-a \
        -e CLIENT_SECRET="$SERVICE_A_CLIENT_SECRET" \
        -e SERVICE_B_URL=http://service-b:5001 \
        "$IMAGE"

    wait_for_container_health service-a
    wait_for_service_a_http
    echo "[OK] service-a cold (cache OFF)"
}

configure_gateway_for_performance() {
    echo "[SETUP] Raising Kong rate limit for performance testing..."
    KONG_RATE_LIMIT_MINUTE="$PERFORMANCE_RATE_LIMIT_MINUTE"         "$COMPOSE_DIR/scripts/setup-kong.sh"
    echo "[OK] Performance rate limit applied: $PERFORMANCE_RATE_LIMIT_MINUTE/minute"
}

restore_artifact_state() {
    local exit_code=$?

    trap - EXIT INT TERM
    set +e

    echo ""
    echo "[CLEANUP] Restoring normal Service A and Kong configuration..."

    run_service_a_normal

    KONG_RATE_LIMIT_MINUTE="$ORIGINAL_RATE_LIMIT_MINUTE"         "$COMPOSE_DIR/scripts/setup-kong.sh"

    echo "[CLEANUP] Kong rate limit restored to $ORIGINAL_RATE_LIMIT_MINUTE/minute"
    exit "$exit_code"
}

mkdir -p "$COMPOSE_DIR/performance/results"

wait_for_oidc
wait_for_container_health kong
wait_for_container_health service-b

trap restore_artifact_state EXIT INT TERM
configure_gateway_for_performance

for RUN in $(seq 1 "$RUN_COUNT"); do
    echo ""
    echo "════════════════════════════════════════"
    echo " RUN $RUN"
    echo "════════════════════════════════════════"

    echo "[RUN $RUN] Condition A: baseline..."
    run_service_a_normal
    k6 run --out json="$COMPOSE_DIR/performance/results/k6_A_run${RUN}.json" "$K6_DIR/test_A_baseline.js"
    echo "[RUN $RUN] Condition A completed"

    echo "[RUN $RUN] Condition B: cold cache..."
    docker restart service-b >/dev/null
    wait_for_container_health service-b
    wait_for_oidc
    run_service_a_cold
    k6 run --out json="$COMPOSE_DIR/performance/results/k6_B_run${RUN}.json" "$K6_DIR/test_B_cold.js"
    echo "[RUN $RUN] Condition B completed"

    echo "[RUN $RUN] Condition C: warm cache..."
    run_service_a_normal
    warm_up_aiem_path
    k6 run --out json="$COMPOSE_DIR/performance/results/k6_C_run${RUN}.json" "$K6_DIR/test_C_warm.js"
    echo "[RUN $RUN] Condition C completed"

    if [ "$RUN" -lt "$RUN_COUNT" ] && [ "$COOLDOWN_SECONDS" -gt 0 ]; then
        echo "[COOLDOWN] Waiting $COOLDOWN_SECONDS seconds before Run $((RUN+1))..."
        sleep "$COOLDOWN_SECONDS"
        echo "[COOLDOWN] Done."
    fi
done

echo ""
echo "════════════════════════════════════════"
echo " ALL RUNS COMPLETED"
echo "════════════════════════════════════════"
