#!/bin/bash
set -euo pipefail

MODE="${1:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "$MODE" ]; then
    echo "Usage: $0 baseline|aiem-warm|aiem-cold|restore" >&2
    exit 1
fi

if [ ! -f "$COMPOSE_DIR/.env" ]; then
    echo "ERROR: .env file is required. Copy .env.example to .env first." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
source "$COMPOSE_DIR/.env"
set +a

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$COMPOSE_DIR")}"
NETWORK="${DOCKER_NETWORK:-${PROJECT_NAME}_zero-trust-net}"
SERVICE_A_IMAGE="${SERVICE_A_IMAGE:-${PROJECT_NAME}-service-a}"
KEYCLOAK_TOKEN_URL="${KEYCLOAK_TOKEN_URL:-http://localhost:8080/realms/zero-trust/protocol/openid-connect/token}"

: "${SERVICE_A_CLIENT_SECRET:?SERVICE_A_CLIENT_SECRET environment variable is required}"

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

set_service_b_pdp() {
    local pdp_mode="$1"

    echo "[SETUP] Recreating Service B with AIEM_PDP_MODE=$pdp_mode"
    cd "$COMPOSE_DIR"
    AIEM_PDP_MODE="$pdp_mode" docker compose --env-file "$COMPOSE_DIR/.env" up -d --force-recreate --no-deps service-b
    wait_for_container_health service-b

    echo "[VERIFY] Service B runtime PDP mode:"
    docker exec service-b printenv AIEM_PDP_MODE
}

run_service_a_normal() {
    echo "[SETUP] Recreating Service A with token cache enabled"
    docker stop service-a 2>/dev/null || true
    docker rm service-a 2>/dev/null || true

    cd "$COMPOSE_DIR"
    docker compose --env-file "$COMPOSE_DIR/.env" up -d --force-recreate --no-deps service-a

    wait_for_container_health service-a
    wait_for_service_a_http

    echo "[OK] Service A normal mode: token cache ON"
}

run_service_a_cold() {
    echo "[SETUP] Recreating Service A with token cache disabled"
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
        "$SERVICE_A_IMAGE" >/dev/null

    wait_for_container_health service-a
    wait_for_service_a_http

    echo "[OK] Service A cold mode: token cache OFF"
}

case "$MODE" in
    baseline)
        echo "[MODE] baseline: same secure path, Service B PDP OFF, Service A cache ON"
        set_service_b_pdp off
        run_service_a_normal
        ;;

    aiem-warm)
        echo "[MODE] aiem-warm: same secure path, Service B PDP ON, Service A cache ON"
        set_service_b_pdp on
        run_service_a_normal
        ;;

    aiem-cold)
        echo "[MODE] aiem-cold: Service B PDP ON, Service B JWKS cache reset, Service A token cache OFF"
        set_service_b_pdp on
        run_service_a_cold
        ;;

    restore)
        echo "[MODE] restore: normal artifact state"
        set_service_b_pdp on
        run_service_a_normal
        ;;

    *)
        echo "ERROR: unknown mode: $MODE" >&2
        echo "Usage: $0 baseline|aiem-warm|aiem-cold|restore" >&2
        exit 1
        ;;
esac

echo "[DONE] Performance mode applied: $MODE"
