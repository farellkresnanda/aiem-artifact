import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const mC   = new Trend('condC_warm_latency_ms', true);
const errC = new Rate('condC_error_rate');

const BASE   = __ENV.KONG_PROXY_URL || 'http://localhost:8000';
const KCLOAK = __ENV.KEYCLOAK_TOKEN_URL || 'http://localhost:8080/realms/zero-trust/protocol/openid-connect/token';
const TEST_USERNAME = __ENV.K6_TEST_USERNAME || 'testuser';
const TEST_PASSWORD = __ENV.K6_TEST_PASSWORD;

export const options = {
    stages: [
        { duration: '15s',  target: 10 },
        { duration: '120s', target: 10 },
        { duration: '15s',  target: 0  },
    ],
    thresholds: { condC_error_rate: ['rate<0.01'] },
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
    return { token: JSON.parse(r.body).access_token };
}

export default function(data) {
    const r = http.get(
        `${BASE}/api/a/api/fetch-employee-secure/1`,
        { headers: { Authorization: `Bearer ${data.token}` } }
    );
    mC.add(r.timings.duration);
    errC.add(r.status !== 200);
    check(r, { 'C-200': (r) => r.status === 200 });
    sleep(0.5);
}
