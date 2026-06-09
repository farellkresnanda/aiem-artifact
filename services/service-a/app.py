from flask import Flask, request, jsonify
import requests as http_req, os, time

app = Flask(__name__)

KEYCLOAK_TOKEN_URL = os.getenv('KEYCLOAK_TOKEN_URL')
CLIENT_ID         = os.getenv('CLIENT_ID', 'service-a')
CLIENT_SECRET     = os.getenv('CLIENT_SECRET')
SERVICE_B_URL     = os.getenv('SERVICE_B_URL', 'http://service-b:5001')

# M2M token cache
_m2m_cache = {'token': None, 'expires_at': 0}

def get_m2m_token():
    if not CLIENT_SECRET:
        raise RuntimeError("CLIENT_SECRET environment variable is required")
    now = time.time()
    # DISABLE_M2M_CACHE=true → skip cache and always fetch a fresh token for cold-cache testing
    if os.getenv('DISABLE_M2M_CACHE', 'false') != 'true':
        if _m2m_cache['token'] and _m2m_cache['expires_at'] > now + 30:
            return _m2m_cache['token']
    r = http_req.post(KEYCLOAK_TOKEN_URL, data={
        'grant_type': 'client_credentials',
        'client_id': CLIENT_ID,
        'client_secret': CLIENT_SECRET,
        'scope': 'service.read.public'
    })
    data = r.json()
    _m2m_cache['token'] = data['access_token']
    _m2m_cache['expires_at'] = now + data.get('expires_in', 300)
    return _m2m_cache['token']

@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'service': 'entry-point-a'})

# BASELINE: Call Service B without an M2M token to simulate the non-AIEM path
@app.route('/api/fetch-employee/<int:emp_id>')
def fetch_traditional(emp_id):
    resp = http_req.get(f'{SERVICE_B_URL}/internal/employees/{emp_id}', timeout=5)
    return jsonify({'mode': 'TRADITIONAL_NO_M2M',
                    'http_status': resp.status_code,
                    'data': resp.json()})

# AIEM: Call Service B with an M2M token
@app.route('/api/fetch-employee-secure/<int:emp_id>')
def fetch_secure(emp_id):
    token = get_m2m_token()
    resp = http_req.get(f'{SERVICE_B_URL}/secure/employees/{emp_id}',
                        headers={'Authorization': f'Bearer {token}'}, timeout=5)
    return jsonify({'mode': 'ZERO_TRUST_M2M',
                    'http_status': resp.status_code,
                    'data': resp.json()})

# SSRF SIMULATION: Attacker-controlled target URL (CWE-918)
@app.route('/api/internal-fetch')
def ssrf_simulate():
    target = request.args.get('target', '')
    emp_id = request.args.get('emp_id', '1')
    if not target:
        return jsonify({'error': 'target parameter required'}), 400
    try:
        resp = http_req.get(f'http://{target}/internal/employees/{emp_id}', timeout=3)
        return jsonify({'ssrf_target': target, 'emp_id': emp_id, 'data': resp.json()})
    except Exception as e:
        return jsonify({'ssrf_target': target, 'error': str(e)}), 502

# CREDENTIAL EXPOSURE: Simulated RCE/LFI endpoint for scenario S7
@app.route('/api/debug/env')
def debug_env():
    if os.getenv('ENABLE_SIMULATED_SECRET_LEAK', 'false') != 'true':
        return jsonify({
            'error': 'simulated secret leak endpoint is disabled',
            'hint': 'set ENABLE_SIMULATED_SECRET_LEAK=true only when reproducing scenario S7'
        }), 403

    return jsonify({
        'CLIENT_ID':     os.getenv('CLIENT_ID'),
        'CLIENT_SECRET': os.getenv('CLIENT_SECRET'),
        'KEYCLOAK_URL':  os.getenv('KEYCLOAK_TOKEN_URL'),
        'warning':       'THIS IS A SIMULATED VULNERABILITY FOR RESEARCH ONLY'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
