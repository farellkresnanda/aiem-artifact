#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
K6_DIR="$SCRIPT_DIR"
MODE_SCRIPT="$COMPOSE_DIR/scripts/set-performance-mode.sh"
K6_SCRIPT="$K6_DIR/performance_test.js"

if [ -f "$COMPOSE_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$COMPOSE_DIR/.env"
    set +a
fi

command -v k6 >/dev/null 2>&1 || {
    echo "ERROR: k6 is required to run performance tests." >&2
    exit 1
}

[ -x "$MODE_SCRIPT" ] || {
    echo "ERROR: $MODE_SCRIPT is missing or not executable." >&2
    exit 1
}

[ -f "$K6_SCRIPT" ] || {
    echo "ERROR: $K6_SCRIPT is missing." >&2
    exit 1
}

REPETITIONS="${REPETITIONS:-${RUN_COUNT:-1}}"
ORDER_PLAN="${ORDER_PLAN:-ABC,ACB,BAC,BCA,CAB,CBA}"

COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-120}"
WARMUP_SECONDS="${WARMUP_SECONDS:-20}"
WARMUP_REQUESTS="${WARMUP_REQUESTS:-20}"

PERFORMANCE_RATE_LIMIT_MINUTE="${PERFORMANCE_RATE_LIMIT_MINUTE:-100000}"
ORIGINAL_RATE_LIMIT_MINUTE="${KONG_RATE_LIMIT_MINUTE:-120}"

TARGET_PATH="${TARGET_PATH:-/api/a/api/fetch-employee-secure/1}"
EXPECTED_STATUS="${EXPECTED_STATUS:-200}"

K6_RAMP_UP="${K6_RAMP_UP:-30s}"
K6_STEADY="${K6_STEADY:-90s}"
K6_RAMP_DOWN="${K6_RAMP_DOWN:-30s}"
K6_MAX_VUS="${K6_MAX_VUS:-10}"
K6_SLEEP_SECONDS="${K6_SLEEP_SECONDS:-0.5}"

: "${SERVICE_A_CLIENT_SECRET:?SERVICE_A_CLIENT_SECRET environment variable is required}"
: "${K6_TEST_PASSWORD:?K6_TEST_PASSWORD environment variable is required}"

export KONG_PROXY_URL="${KONG_PROXY_URL:-http://localhost:8000}"
export KEYCLOAK_TOKEN_URL="${KEYCLOAK_TOKEN_URL:-http://localhost:8080/realms/zero-trust/protocol/openid-connect/token}"
export K6_TEST_USERNAME="${K6_TEST_USERNAME:-testuser}"

mkdir -p "$COMPOSE_DIR/performance/results"

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

get_user_token() {
    curl -fsS -X POST "$KEYCLOAK_TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=password" \
        --data-urlencode "client_id=webapp-client" \
        --data-urlencode "username=$K6_TEST_USERNAME" \
        --data-urlencode "password=$K6_TEST_PASSWORD" \
    | jq -r '.access_token // empty'
}

warm_up_target_path() {
    local label="$1"
    local token
    local i

    echo "[WARMUP] $label: priming same target path $TARGET_PATH"

    token="$(get_user_token)"
    if [ -z "$token" ]; then
        echo "ERROR: failed to obtain user token for warmup" >&2
        return 1
    fi

    for i in $(seq 1 "$WARMUP_REQUESTS"); do
        curl -fsS \
            -H "Authorization: Bearer $token" \
            "$KONG_PROXY_URL$TARGET_PATH" >/dev/null
    done

    if [ "$WARMUP_SECONDS" -gt 0 ]; then
        echo "[WARMUP] $label: waiting $WARMUP_SECONDS seconds..."
        sleep "$WARMUP_SECONDS"
    fi

    echo "[OK] $label warmup completed"
}

configure_gateway_for_performance() {
    echo "[SETUP] Raising Kong rate limit for performance testing..."
    KONG_RATE_LIMIT_MINUTE="$PERFORMANCE_RATE_LIMIT_MINUTE" \
        "$COMPOSE_DIR/scripts/setup-kong.sh"
    echo "[OK] Performance rate limit applied: $PERFORMANCE_RATE_LIMIT_MINUTE/minute"
}

restore_artifact_state() {
    local exit_code=$?

    trap - EXIT INT TERM
    set +e

    echo ""
    echo "[CLEANUP] Restoring normal artifact state..."
    unset AIEM_PDP_MODE
    "$MODE_SCRIPT" restore

    KONG_RATE_LIMIT_MINUTE="$ORIGINAL_RATE_LIMIT_MINUTE" \
        "$COMPOSE_DIR/scripts/setup-kong.sh"

    echo "[CLEANUP] Kong rate limit restored to $ORIGINAL_RATE_LIMIT_MINUTE/minute"
    exit "$exit_code"
}

run_k6_condition() {
    local condition="$1"
    local repetition="$2"
    local block="$3"
    local position="$4"
    local label
    local output_file

    case "$condition" in
        A)
            label="condA_baseline_same_path"
            echo "[MODE] Condition A: same-path baseline, PDP OFF, cache warm"
            unset AIEM_PDP_MODE
            "$MODE_SCRIPT" baseline
            warm_up_target_path "$label"
            ;;
        B)
            label="condB_aiem_cold_cache"
            echo "[MODE] Condition B: AIEM cold cache, PDP ON, Service A token cache OFF"
            unset AIEM_PDP_MODE
            "$MODE_SCRIPT" aiem-cold
            ;;
        C)
            label="condC_aiem_warm_cache"
            echo "[MODE] Condition C: AIEM warm cache, PDP ON, cache warm"
            unset AIEM_PDP_MODE
            "$MODE_SCRIPT" aiem-warm
            warm_up_target_path "$label"
            ;;
        *)
            echo "ERROR: unknown condition: $condition" >&2
            return 1
            ;;
    esac

    output_file="$COMPOSE_DIR/performance/results/k6_${condition}_rep${repetition}_block${block}_pos${position}.json"

    echo "[K6] Running $label"
    echo "[K6] Output: $output_file"

    TEST_LABEL="$label" \
    TARGET_PATH="$TARGET_PATH" \
    EXPECTED_STATUS="$EXPECTED_STATUS" \
    K6_RAMP_UP="$K6_RAMP_UP" \
    K6_STEADY="$K6_STEADY" \
    K6_RAMP_DOWN="$K6_RAMP_DOWN" \
    K6_MAX_VUS="$K6_MAX_VUS" \
    K6_SLEEP_SECONDS="$K6_SLEEP_SECONDS" \
    k6 run --out json="$output_file" "$K6_SCRIPT"

    echo "[OK] Completed $label"
}

IFS=',' read -r -a ORDERS <<< "$ORDER_PLAN"

wait_for_oidc
wait_for_container_health kong
wait_for_container_health service-b
wait_for_container_health service-a

trap restore_artifact_state EXIT INT TERM
configure_gateway_for_performance

block_number=0
total_blocks=$(( REPETITIONS * ${#ORDERS[@]} ))

for repetition in $(seq 1 "$REPETITIONS"); do
    for order in "${ORDERS[@]}"; do
        block_number=$((block_number + 1))

        if [[ ! "$order" =~ ^[ABC]{3}$ ]]; then
            echo "ERROR: invalid order '$order'. Use combinations such as ABC,ACB,BAC." >&2
            exit 1
        fi

        echo ""
        echo "════════════════════════════════════════"
        echo " REPETITION $repetition / $REPETITIONS"
        echo " BLOCK $block_number / $total_blocks"
        echo " ORDER $order"
        echo "════════════════════════════════════════"

        for ((pos=0; pos<${#order}; pos++)); do
            condition="${order:pos:1}"
            run_k6_condition "$condition" "$repetition" "$block_number" "$((pos + 1))"
        done

        if [ "$block_number" -lt "$total_blocks" ] && [ "$COOLDOWN_SECONDS" -gt 0 ]; then
            echo "[COOLDOWN] Waiting $COOLDOWN_SECONDS seconds before next block..."
            sleep "$COOLDOWN_SECONDS"
            echo "[COOLDOWN] Done."
        fi
    done
done

echo ""
echo "════════════════════════════════════════"
echo " ALL PERFORMANCE BLOCKS COMPLETED"
echo "════════════════════════════════════════"
