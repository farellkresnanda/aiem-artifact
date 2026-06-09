// cold_test.js
// Kondisi B: M2M token cache kosong, JWKS cache kosong
// Wajib: docker restart service-a service-b && sleep 10 sebelum run

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const mB   = new Trend('condB_cold_latency_ms', true);
const errB = new Rate('condB_error_rate');

const BASE   = __ENV.KONG_PROXY_URL || 'http://localhost:8000';
const KCLOAK = __ENV.KEYCLOAK_TOKEN_URL || 'http://localhost:8080/realms/zero-trust/protocol/openid-connect/token';
const TEST_USERNAME = __ENV.K6_TEST_USERNAME || 'testuser';
const TEST_PASSWORD = __ENV.K6_TEST_PASSWORD;

export const options = {
    stages: [
        { duration: '15s', target: 10 },
        { duration: '120s', target: 10 },
        { duration: '15s', target: 0 },
    ],
    thresholds: {
        condB_error_rate: ['rate<0.01'],
    },
};

export function setup() {
    if (!TEST_PASSWORD) throw new Error('K6_TEST_PASSWORD environment variable is required');

    // Ambil user token sekali — validasi koneksi
    const r = http.post(KCLOAK, {
        grant_type: 'password',
        client_id:  'webapp-client',
        username:   TEST_USERNAME,
        password:   TEST_PASSWORD,
    });
    if (r.status !== 200) throw new Error(`Keycloak error: ${r.status}`);
    return { userToken: JSON.parse(r.body).access_token };
}

export default function(data) {
    // Setiap request ke fetch-employee-secure memaksa Service A
    // fetch M2M token dari Keycloak (cache kosong karena restart)
    // DAN Service B fetch JWKS (cache kosong karena restart)
    const r = http.get(
        `${BASE}/api/a/api/fetch-employee-secure/1`,
        { headers: { Authorization: `Bearer ${data.userToken}` } }
    );

    mB.add(r.timings.duration);
    errB.add(r.status !== 200);
    check(r, { 'B-200': (r) => r.status === 200 });
    sleep(0.5);
}
