#!/usr/bin/env bash
set -euo pipefail

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${KEYCLOAK_ADMIN:?KEYCLOAK_ADMIN is required. Create .env from .env.example first.}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD is required. Create .env from .env.example first.}"
: "${SERVICE_A_CLIENT_SECRET:?SERVICE_A_CLIENT_SECRET is required. Create .env from .env.example first.}"
: "${K6_TEST_USERNAME:?K6_TEST_USERNAME is required. Create .env from .env.example first.}"
: "${K6_TEST_PASSWORD:?K6_TEST_PASSWORD is required. Create .env from .env.example first.}"

REALM="${KEYCLOAK_REALM:-zero-trust}"
KEYCLOAK_CONTAINER="${KEYCLOAK_CONTAINER:-keycloak}"

echo "Waiting for Keycloak to become reachable..."
until docker exec "$KEYCLOAK_CONTAINER" bash -lc 'exec 3<>/dev/tcp/localhost/8080' 2>/dev/null; do
  sleep 3
done

echo "Logging in to Keycloak admin CLI..."
docker exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

echo "Checking realm: $REALM"
docker exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get "realms/$REALM" >/dev/null

echo "Configuring service-a client secret..."
SERVICE_A_CLIENT_ID="$(docker exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get clients \
  -r "$REALM" \
  -q clientId=service-a \
  --fields id \
  --format csv \
  --noquotes | tail -n 1 | tr -d '\r')"

if [ -z "$SERVICE_A_CLIENT_ID" ]; then
  echo "ERROR: service-a client was not found in realm $REALM" >&2
  exit 1
fi

docker exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh update "clients/$SERVICE_A_CLIENT_ID" \
  -r "$REALM" \
  -s "secret=$SERVICE_A_CLIENT_SECRET"

echo "Configuring test user password for: $K6_TEST_USERNAME"
USER_ID="$(docker exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh get users \
  -r "$REALM" \
  -q username="$K6_TEST_USERNAME" \
  --fields id \
  --format csv \
  --noquotes | tail -n 1 | tr -d '\r')"

if [ -z "$USER_ID" ]; then
  echo "Test user does not exist. Creating user: $K6_TEST_USERNAME"
  docker exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh create users \
    -r "$REALM" \
    -s "username=$K6_TEST_USERNAME" \
    -s enabled=true >/dev/null
fi

docker exec "$KEYCLOAK_CONTAINER" /opt/keycloak/bin/kcadm.sh set-password \
  -r "$REALM" \
  --username "$K6_TEST_USERNAME" \
  --new-password "$K6_TEST_PASSWORD" \
  --temporary=false

echo "Keycloak local reproduction settings applied."
