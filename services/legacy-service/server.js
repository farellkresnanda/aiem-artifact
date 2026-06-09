const express = require('express');
const app = express();
app.use(express.json());

// Intentionally vulnerable baseline dataset for security evaluation only
const users = [
    { id: 1,  name: 'Alice', role: 'user',  sensitive_id: 'SIMULATED-USER-ID' },
    { id: 99, name: 'Admin', role: 'admin', simulated_secret: 'SIMULATED-LEGACY-SECRET' }
];

// OWASP API1: BOLA — tidak ada cek apakah user berhak akses ID ini
app.get('/profile/:id', (req, res) => {
    const user = users.find(u => u.id === parseInt(req.params.id));
    if (user) return res.json(user);
    return res.status(404).json({ error: 'Not found' });
});

// OWASP API5: Broken Function Level AuthZ
app.get('/admin', (req, res) => {
    return res.json({ message: 'Admin Panel', simulated_credentials: users[1].simulated_secret });
});

app.get('/health', (req, res) => res.json({ status: 'ok', service: 'legacy-api' }));

app.listen(3000, '0.0.0.0', () => console.log('[LEGACY] Running on port 3000'));
