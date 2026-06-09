#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
K6_DIR="$SCRIPT_DIR"

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$COMPOSE_DIR")}"
NETWORK="${DOCKER_NETWORK:-${PROJECT_NAME}_zero-trust-net}"
IMAGE="${SERVICE_A_IMAGE:-${PROJECT_NAME}-service-a}"

: "${SERVICE_A_CLIENT_SECRET:?SERVICE_A_CLIENT_SECRET environment variable is required}"
: "${K6_TEST_PASSWORD:?K6_TEST_PASSWORD environment variable is required}"

export KONG_PROXY_URL="${KONG_PROXY_URL:-http://localhost:8000}"
export KEYCLOAK_TOKEN_URL="${KEYCLOAK_TOKEN_URL:-http://localhost:8080/realms/zero-trust/protocol/openid-connect/token}"
export K6_TEST_USERNAME="${K6_TEST_USERNAME:-testuser}"

run_service_a_normal() {
    docker stop service-a 2>/dev/null || true
    docker rm service-a 2>/dev/null || true
    cd "$COMPOSE_DIR" && docker compose up -d service-a
    sleep 8
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

    sleep 8
    echo "[OK] service-a cold (cache OFF)"
}

mkdir -p "$COMPOSE_DIR/performance/results"

for RUN in 1 2 3 4 5; do
    echo ""
    echo "════════════════════════════════════════"
    echo " RUN $RUN"
    echo "════════════════════════════════════════"

    echo "[RUN $RUN] Condition A: baseline..."
    run_service_a_normal
    k6 run --out json="$COMPOSE_DIR/performance/results/k6_A_run${RUN}.json" "$K6_DIR/test_A_baseline.js"
    echo "[RUN $RUN] Condition A completed"

    echo "[RUN $RUN] Condition B: cold cache..."
    docker restart service-b && sleep 10
    run_service_a_cold
    k6 run --out json="$COMPOSE_DIR/performance/results/k6_B_run${RUN}.json" "$K6_DIR/test_B_cold.js"
    echo "[RUN $RUN] Condition B completed"

    echo "[RUN $RUN] Condition C: warm cache..."
    run_service_a_normal
    k6 run --out json="$COMPOSE_DIR/performance/results/k6_C_run${RUN}.json" "$K6_DIR/test_C_warm.js"
    echo "[RUN $RUN] Condition C completed"

    if [ "$RUN" -lt 5 ]; then
        echo "[COOLDOWN] Waiting 120 seconds before Run $((RUN+1))..."
        sleep 120
        echo "[COOLDOWN] Done."
    fi
done

run_service_a_normal

echo ""
echo "════════════════════════════════════════"
echo " ALL RUNS COMPLETED"
echo "════════════════════════════════════════"
