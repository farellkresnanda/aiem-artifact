// baseline_warm_test.js
// Kondisi A: baseline tanpa enforcement
// Kondisi C: AIEM warm cache (M2M token cached di Service A, JWKS cached di Service B)
// Jalankan SETELAH cold_test.js selesai — jangan restart service

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const mA   = new Trend('condA_baseline_latency_ms', true);
const mC   = new Trend('condC_warm_latency_ms', true);
const errA = new Rate('condA_error_rate');
const errC = new Rate('condC_error_rate');

const BASE   = __ENV.KONG_PROXY_URL || 'http://localhost:8000';
const KCLOAK = __ENV.KEYCLOAK_TOKEN_URL || 'http://localhost:8080/realms/zero-trust/protocol/openid-connect/token';
const TEST_USERNAME = __ENV.K6_TEST_USERNAME || 'testuser';
const TEST_PASSWORD = __ENV.K6_TEST_PASSWORD;

export const options = {
    scenarios: {
        // Kondisi A dan C jalan bersamaan — load identik, timing identik
        // Ini paling fair karena kondisi VM sama persis di waktu yang sama
        condition_A: {
            executor:    'ramping-vus',
            startVUs:    0,
            stages: [
                { duration: '15s',  target: 10 },
                { duration: '120s', target: 10 },
                { duration: '15s',  target: 0  },
            ],
            gracefulRampDown: '10s',
            exec: 'runA',
        },
        condition_C: {
            executor:    'ramping-vus',
            startVUs:    0,
            stages: [
                { duration: '15s',  target: 10 },
                { duration: '120s', target: 10 },
                { duration: '15s',  target: 0  },
            ],
            gracefulRampDown: '10s',
            exec: 'runC',
        },
    },
    thresholds: {
        condA_error_rate: ['rate<0.01'],
        condC_error_rate: ['rate<0.01'],
    },
};

export function setup() {
    if (!TEST_PASSWORD) throw new Error('K6_TEST_PASSWORD environment variable is required');
    const r = http.post(KCLOAK, {
        grant_type: 'password',
        client_id:  'webapp-client',
        username:   TEST_USERNAME,
        password:   TEST_PASSWORD,
    });
    if (r.status !== 200) throw new Error(`Keycloak error: ${r.status}`);
    return { userToken: JSON.parse(r.body).access_token };
}

// Kondisi A: tanpa M2M, tanpa Vpdp — Service A hit /internal di Service B
export function runA(data) {
    const r = http.get(
        `${BASE}/api/a/api/fetch-employee/1`,
        { headers: { Authorization: `Bearer ${data.userToken}` } }
    );
    mA.add(r.timings.duration);
    errA.add(r.status !== 200);
    check(r, { 'A-200': (r) => r.status === 200 });
    sleep(0.5);
}

// Kondisi C: dengan M2M, dengan Vpdp — cache sudah warm
export function runC(data) {
    const r = http.get(
        `${BASE}/api/a/api/fetch-employee-secure/1`,
        { headers: { Authorization: `Bearer ${data.userToken}` } }
    );
    mC.add(r.timings.duration);
    errC.add(r.status !== 200);
    check(r, { 'C-200': (r) => r.status === 200 });
    sleep(0.5);
}
