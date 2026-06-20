from flask import Flask, request, jsonify
import requests as http_req, os, jwt, json, time

app = Flask(__name__)
KEYCLOAK_JWKS_URL = os.getenv('KEYCLOAK_JWKS_URL')
AIEM_PDP_MODE = os.getenv('AIEM_PDP_MODE', 'on').strip().lower()

def is_pdp_enabled():
    return AIEM_PDP_MODE not in ('off', 'false', '0', 'disabled')

# JWKS Cache with 300-second TTL (auto-refresh on expiry)
_jwks_cache = {'keys': None, 'fetched_at': 0}
JWKS_TTL_SECONDS = 300

def get_jwks():
    now = time.time()
    if _jwks_cache['keys'] and (now - _jwks_cache['fetched_at']) < JWKS_TTL_SECONDS:
        return _jwks_cache['keys']
    r = http_req.get(KEYCLOAK_JWKS_URL, timeout=10)
    r.raise_for_status()
    _jwks_cache['keys']       = r.json()
    _jwks_cache['fetched_at'] = now
    return _jwks_cache['keys']

# Highly sensitive downstream dataset used for security evaluation
EMPLOYEES = [
    {'id': 1,  'name': 'Alice', 'role': 'staff',     'salary': 8000},
    {'id': 2,  'name': 'Bob',   'role': 'staff',     'salary': 8500},
    {'id': 99, 'name': 'CEO',   'role': 'executive', 'salary': 50000,
               'sensitive_id': 'SIMULATED-SENSITIVE-ID', 'bank_record': 'SIMULATED-SENSITIVE-FIELD'}
]

def verify_m2m_token(token):
    """Validate M2M token: signature + aud + azp + scope (V_pdp)"""
    try:
        jwks = get_jwks()
        keys = {}
        for k in jwks.get('keys', []):
            if k.get('kty') == 'RSA':
                keys[k['kid']] = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(k))
        header  = jwt.get_unverified_header(token)
        payload = jwt.decode(
            token,
            keys[header['kid']],
            algorithms=['RS256'],
            audience='service-b',        # MVCS Claim 4
            options={'verify_aud': True}
        )
        if payload.get('azp') != 'service-a':           # MVCS Claim 5
            return None, 'REJECTED: azp mismatch — caller is not service-a'
        if 'service.read' not in payload.get('scope', ''):  # MVCS Claim 6
            return None, 'REJECTED: missing required scope service.read'
        return payload, None
    except jwt.InvalidAudienceError:
        return None, 'REJECTED: token audience is not service-b'
    except jwt.ExpiredSignatureError:
        return None, 'REJECTED: token has expired'
    except Exception as e:
        return None, f'REJECTED: {str(e)}'

def verify_user_token(token):
    """Validate regular user token (for /public endpoint)"""
    try:
        jwks = get_jwks()
        keys = {
            k['kid']: jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(k))
            for k in jwks.get('keys', []) if k.get('kty') == 'RSA'
        }
        header  = jwt.get_unverified_header(token)
        payload = jwt.decode(
            token,
            keys[header['kid']],
            algorithms=['RS256'],
            options={'verify_aud': False}
        )
        if payload.get('azp') == 'service-a':
            return None, 'REJECTED: M2M token is not allowed on public endpoint'
        return payload, None
    except jwt.ExpiredSignatureError:
        return None, 'REJECTED: token has expired'
    except Exception as e:
        return None, f'REJECTED: {str(e)}'

@app.route('/health')
def health():
    return jsonify({
        'status': 'ok',
        'service': 'highly-sensitive-b',
        'pdp_mode': AIEM_PDP_MODE
    })

# BASELINE (internal): No token — network perimeter only
@app.route('/internal/employees/<int:emp_id>')
def internal_get(emp_id):
    emp = next((e for e in EMPLOYEES if e['id'] == emp_id), None)
    if emp:
        return jsonify(emp)
    return jsonify({'error': 'not found'}), 404

# ZERO TRUST: Requires M2M token from service-a — exposed via Kong /api/b
@app.route('/secure/employees/<int:emp_id>')
def secure_get(emp_id):
    auth = request.headers.get('Authorization', '')
    if not auth.startswith('Bearer '):
        return jsonify({
            'error':     'M2M token required',
            'zt_status': 'REJECTED',
            'layer':     'Service-B-Inline-PDP'
        }), 401

    # Performance baseline mode: keep the same /secure endpoint and M2M request path,
    # but bypass the resource-level PDP checks. Default mode remains PDP ON.
    if not is_pdp_enabled():
        emp = next((e for e in EMPLOYEES if e['id'] == emp_id), None)
        if not emp:
            return jsonify({'error': 'not found'}), 404

        if emp['role'] == 'staff':
            return jsonify({
                'id':        emp['id'],
                'name':      emp['name'],
                'role':      emp['role'],
                'zt_status': 'PDP_DISABLED_BASELINE'
            })

        return jsonify({**emp, 'zt_status': 'PDP_DISABLED_BASELINE'})

    payload, err = verify_m2m_token(auth.split(' ')[1])
    if err:
        return jsonify({
            'error':     err,
            'zt_status': 'REJECTED',
            'layer':     'Service-B-Inline-PDP'
        }), 403

    scope = payload.get('scope', '')

    # BOLA Prevention: ID 99 requires executive scope
    if emp_id == 99 and 'service.read.executive' not in scope:
        return jsonify({
            'error':     'BOLA prevented by Application-Identity Model',
            'zt_status': 'BLOCKED',
            'layer':     'Service-B-Scope-Enforcement',
            'azp':       payload.get('azp'),
            'scope':     scope
        }), 403

    emp = next((e for e in EMPLOYEES if e['id'] == emp_id), None)
    if not emp:
        return jsonify({'error': 'not found'}), 404

    # Data masking: staff receives non-sensitive fields only
    if 'service.read.public' in scope and emp['role'] == 'staff':
        return jsonify({
            'id':        emp['id'],
            'name':      emp['name'],
            'role':      emp['role'],
            'zt_status': 'ALLOWED_MASKED'
        })

    return jsonify({**emp, 'zt_status': 'ALLOWED_FULL'})

# PUBLIC: Accepts regular user token — exposed via Kong /api/b-public
@app.route('/public/employees/<int:emp_id>')
def public_get(emp_id):
    auth = request.headers.get('Authorization', '')
    if not auth.startswith('Bearer '):
        return jsonify({
            'error':     'token required',
            'zt_status': 'REJECTED'
        }), 401

    payload, err = verify_user_token(auth.split(' ')[1])
    if err:
        return jsonify({
            'error':     err,
            'zt_status': 'REJECTED',
            'note':      'this endpoint requires a user token, not an M2M token'
        }), 403

    emp = next((e for e in EMPLOYEES if e['id'] == emp_id), None)
    if not emp:
        return jsonify({'error': 'not found'}), 404

    if emp['role'] == 'executive':
        return jsonify({
            'error':     'executive data not accessible on public endpoint',
            'zt_status': 'BLOCKED_PUBLIC_POLICY'
        }), 403

    return jsonify({
        'id':        emp['id'],
        'name':      emp['name'],
        'role':      emp['role'],
        'zt_status': 'ALLOWED_USER_TOKEN'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=False)
