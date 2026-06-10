#!/bin/bash
set -e

python3 -c 'import cryptography' >/dev/null 2>&1 || {
  echo "ERROR: Python cryptography package is required." >&2
  echo "On Ubuntu, install it with: sudo apt install python3-cryptography" >&2
  exit 1
}

KONG="${KONG_ADMIN_URL:-http://localhost:8001}"
KEYCLOAK_ISSUER="${KEYCLOAK_ISSUER:-http://localhost:8080/realms/zero-trust}"
KEYCLOAK_JWKS_URL="${KEYCLOAK_JWKS_URL:-${KEYCLOAK_ISSUER}/protocol/openid-connect/certs}"

echo '=== [1/5] Clearing existing Kong configuration ==='
for t in plugins consumers routes services; do
  for id in $(curl -s "$KONG/$t" | python3 -c "import sys,json;[print(x['id']) for x in json.load(sys.stdin).get('data',[])]" 2>/dev/null); do
    curl -s -X DELETE "$KONG/$t/$id" > /dev/null
  done
done

echo '=== [2/5] Registering Kong services ==='
curl -s -X POST "$KONG/services" -d 'name=svc-a' -d 'url=http://service-a:5000' > /dev/null
curl -s -X POST "$KONG/services" -d 'name=svc-b' -d 'url=http://service-b:5001' > /dev/null
curl -s -X POST "$KONG/services" -d 'name=svc-b-pub' -d 'url=http://service-b:5001' > /dev/null
curl -s -X POST "$KONG/services" -d 'name=legacy' -d 'url=http://legacy-service:3000' > /dev/null

echo '=== [3/5] Registering Kong routes ==='
curl -s -X POST "$KONG/services/svc-a/routes" -d 'name=route-a' -d 'paths[]=/api/a' -d 'strip_path=true' > /dev/null
curl -s -X POST "$KONG/services/svc-b/routes" -d 'name=route-b' -d 'paths[]=/api/b' -d 'strip_path=true' > /dev/null
curl -s -X POST "$KONG/services/svc-b-pub/routes" -d 'name=route-b-public' -d 'paths[]=/api/b-public' -d 'strip_path=true' > /dev/null
curl -s -X POST "$KONG/services/legacy/routes" -d 'name=route-legacy' -d 'paths[]=/api/legacy' -d 'strip_path=true' > /dev/null

echo '=== [4/5] Extracting Keycloak public key to PEM ==='
JWKS=$(curl -s "$KEYCLOAK_JWKS_URL")
python3 -c "
import json, base64, sys
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicNumbers
from cryptography.hazmat.primitives import serialization
j = json.loads(sys.argv[1])
k = [x for x in j['keys'] if x.get('kty') == 'RSA' and x.get('use') == 'sig'][0]
def b64(v):
    v = v.replace('-', '+').replace('_', '/')
    v += '=' * (4 - len(v) % 4)
    return int.from_bytes(base64.b64decode(v), 'big')
pk = RSAPublicNumbers(b64(k['e']), b64(k['n'])).public_key()
open('/tmp/kc.pem', 'w').write(pk.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode())
" "$JWKS"

echo '=== [5/5] Registering JWT plugin on all services ==='
curl -s -X POST "$KONG/consumers" -d 'username=keycloak' > /dev/null
curl -s -X POST "$KONG/consumers/keycloak/jwt" -F 'algorithm=RS256' -F "key=$KEYCLOAK_ISSUER" -F 'rsa_public_key=</tmp/kc.pem' > /dev/null

for svc in svc-a svc-b svc-b-pub legacy; do
  curl -s -X POST "$KONG/services/$svc/plugins" -d 'name=jwt' -d 'config.claims_to_verify=exp' -d 'config.key_claim_name=iss' -d 'config.secret_is_base64=false' > /dev/null
done

curl -s -X POST "$KONG/plugins" -d 'name=rate-limiting' -d 'config.minute=120' > /dev/null

echo ''
echo '=== KONG SETUP COMPLETED ==='
echo 'Registered routes:'
curl -s "$KONG/routes" | python3 -c "import sys,json;[print(f\"  {r['name']}: {r['paths']}\") for r in json.load(sys.stdin)['data']]"
