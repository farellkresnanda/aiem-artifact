import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const TEST_LABEL = __ENV.TEST_LABEL || 'condition';
const BASE = __ENV.KONG_PROXY_URL || 'http://localhost:8000';
const KCLOAK = __ENV.KEYCLOAK_TOKEN_URL || 'http://localhost:8080/realms/zero-trust/protocol/openid-connect/token';

const TARGET_PATH = __ENV.TARGET_PATH || '/api/a/api/fetch-employee-secure/1';
const EXPECTED_STATUS = Number(__ENV.EXPECTED_STATUS || '200');

const USERNAME = __ENV.K6_TEST_USERNAME || 'testuser';
const PASSWORD = __ENV.K6_TEST_PASSWORD;

const RAMP_UP = __ENV.K6_RAMP_UP || '30s';
const STEADY = __ENV.K6_STEADY || '90s';
const RAMP_DOWN = __ENV.K6_RAMP_DOWN || '30s';
const MAX_VUS = Number(__ENV.K6_MAX_VUS || '10');
const SLEEP_SECONDS = Number(__ENV.K6_SLEEP_SECONDS || '0.5');

const latencyMetricName = `${TEST_LABEL}_latency_ms`;
const errorMetricName = `${TEST_LABEL}_error_rate`;

const latency = new Trend(latencyMetricName, true);
const errorRate = new Rate(errorMetricName);

export const options = {
    stages: [
        { duration: RAMP_UP, target: MAX_VUS },
        { duration: STEADY, target: MAX_VUS },
        { duration: RAMP_DOWN, target: 0 },
    ],
    thresholds: {
        [errorMetricName]: ['rate<0.01'],
    },
};

export function setup() {
    if (!PASSWORD) {
        throw new Error('K6_TEST_PASSWORD environment variable is required');
    }

    const r = http.post(KCLOAK, {
        grant_type: 'password',
        client_id: 'webapp-client',
        username: USERNAME,
        password: PASSWORD,
    });

    check(r, {
        'token request succeeded': (res) => res.status === 200,
    });

    const token = r.json('access_token');
    if (!token) {
        throw new Error('Failed to obtain user token');
    }

    return { token };
}

export default function (data) {
    const url = `${BASE}${TARGET_PATH}`;

    const r = http.get(url, {
        headers: {
            Authorization: `Bearer ${data.token}`,
        },
    });

    latency.add(r.timings.duration);
    errorRate.add(r.status !== EXPECTED_STATUS);

    check(r, {
        [`${TEST_LABEL}-${EXPECTED_STATUS}`]: (res) => res.status === EXPECTED_STATUS,
    });

    sleep(SLEEP_SECONDS);
}
