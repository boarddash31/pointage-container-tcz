const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PORT = 8085;
const REPO_ROOT = path.resolve(__dirname, '..');
const PUBLIC_DIR = path.resolve(REPO_ROOT, 'site');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.apk': 'application/vnd.android.package-archive',
};

// RPC Cache
const rpcCache = {
  kpis: { data: null, ts: 0, day: '' },
  agents: { data: null, ts: 0 },
  clients_armateurs: { data: null, ts: 0 },
  armateurs: { data: null, ts: 0 }
};

function executeRpc(fnName, params = {}) {
  const env = { ...process.env, NODE_TLS_REJECT_UNAUTHORIZED: '0' };
  const now = Date.now();

  if (fnName === 'admin_dashboard_kpis') {
    const day = params.p_day || new Date().toISOString().split('T')[0];
    if (rpcCache.kpis.data && rpcCache.kpis.day === day && (now - rpcCache.kpis.ts < 6000)) {
      return rpcCache.kpis.data;
    }

    const out = execSync(`npx.cmd supabase db query "SELECT public.admin_dashboard_kpis('${day}');" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    }).toString();

    const jsonMatch = out.match(/\{[\s\S]*"rows":\s*\[([\s\S]*?)\][\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      const res = parsed.rows[0].admin_dashboard_kpis;
      rpcCache.kpis = { data: res, ts: now, day };
      return res;
    }
    throw new Error('Format de réponse Supabase inattendu');
  }

  if (fnName === 'admin_list_agents') {
    if (rpcCache.agents.data && (now - rpcCache.agents.ts < 6000)) {
      return rpcCache.agents.data;
    }

    const out = execSync(`npx.cmd supabase db query "SELECT to_json(a.*) as agent FROM public.admin_list_agents() a;" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    }).toString();

    const jsonMatch = out.match(/\{[\s\S]*"rows":\s*\[([\s\S]*?)\][\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      const agents = parsed.rows.map(r => r.agent);
      rpcCache.agents = { data: agents, ts: now };
      return agents;
    }
    throw new Error('Impossible de lire les agents depuis Supabase');
  }

  if (fnName === 'admin_update_agent') {
    const p = params;
    const sql = `SELECT public.admin_update_agent('${p.p_agent_id}', '${(p.p_first_name || '').replace(/'/g, "''")}', '${(p.p_last_name || '').replace(/'/g, "''")}', '${(p.p_phone || '').replace(/'/g, "''")}', '${p.p_role || 'entree'}', '${(p.p_password || 'tcz123').replace(/'/g, "''")}', ${p.p_active !== false});`;
    execSync(`npx.cmd supabase db query "${sql}" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    });
    rpcCache.agents.ts = 0; // invalidate cache
    return { success: true };
  }

  if (fnName === 'admin_list_clients_armateurs') {
    if (rpcCache.clients_armateurs.data && (now - rpcCache.clients_armateurs.ts < 5000)) {
      return rpcCache.clients_armateurs.data;
    }
    const out = execSync(`npx.cmd supabase db query "SELECT public.admin_list_clients_armateurs();" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    }).toString();
    const jsonMatch = out.match(/\{[\s\S]*"rows":\s*\[([\s\S]*?)\][\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      const res = parsed.rows[0].admin_list_clients_armateurs;
      rpcCache.clients_armateurs = { data: res, ts: now };
      return res;
    }
    throw new Error('Erreur de lecture clients_armateurs');
  }

  if (fnName === 'admin_list_all_armateurs') {
    if (rpcCache.armateurs.data && (now - rpcCache.armateurs.ts < 30000)) {
      return rpcCache.armateurs.data;
    }
    const out = execSync(`npx.cmd supabase db query "SELECT public.admin_list_all_armateurs();" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    }).toString();
    const jsonMatch = out.match(/\{[\s\S]*"rows":\s*\[([\s\S]*?)\][\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      const res = parsed.rows[0].admin_list_all_armateurs;
      rpcCache.armateurs = { data: res, ts: now };
      return res;
    }
    throw new Error('Erreur de lecture all_armateurs');
  }

  if (fnName === 'admin_assign_client_armateur') {
    const { p_client, p_armateur } = params;
    const sql = `SELECT public.admin_assign_client_armateur('${p_client}', '${(p_armateur || '').replace(/'/g, "''")}');`;
    execSync(`npx.cmd supabase db query "${sql}" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    });
    rpcCache.clients_armateurs.ts = 0; // invalidate cache
    return { success: true };
  }

  if (fnName === 'admin_unassign_client_armateur') {
    const { p_client, p_armateur } = params;
    const sql = `SELECT public.admin_unassign_client_armateur('${p_client}', '${(p_armateur || '').replace(/'/g, "''")}');`;
    execSync(`npx.cmd supabase db query "${sql}" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    });
    rpcCache.clients_armateurs.ts = 0; // invalidate cache
    return { success: true };
  }

  if (fnName === 'admin_create_client') {
    const { p_code, p_name } = params;
    const sql = `SELECT public.admin_create_client('${(p_code || '').replace(/'/g, "''")}', '${(p_name || '').replace(/'/g, "''")}');`;
    const out = execSync(`npx.cmd supabase db query "${sql}" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    }).toString();
    rpcCache.clients_armateurs.ts = 0; // invalidate cache
    const jsonMatch = out.match(/\{[\s\S]*"rows":\s*\[([\s\S]*?)\][\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      return parsed.rows[0].admin_create_client;
    }
    return { success: true };
  }

  if (fnName === 'admin_delete_client') {
    const { p_client } = params;
    const sql = `SELECT public.admin_delete_client('${p_client}');`;
    execSync(`npx.cmd supabase db query "${sql}" --linked`, {
      cwd: REPO_ROOT,
      env,
      timeout: 20000
    });
    rpcCache.clients_armateurs.ts = 0; // invalidate cache
    return { success: true };
  }

  throw new Error(`Fonction RPC non reconnue : ${fnName}`);
}

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, apikey, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  const urlPath = req.url.split('?')[0];

  // API RPC Endpoint (Bypasses corporate firewall blocks for localhost)
  if (urlPath.startsWith('/api/rpc/')) {
    const fnName = urlPath.replace('/api/rpc/', '');
    let bodyStr = '';
    req.on('data', chunk => bodyStr += chunk);
    req.on('end', () => {
      let params = {};
      try {
        if (bodyStr) params = JSON.parse(bodyStr);
      } catch (_) {}

      try {
        const result = executeRpc(fnName, params);
        res.writeHead(200, {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache'
        });
        res.end(JSON.stringify(result));
      } catch (err) {
        console.error(`Erreur RPC [${fnName}]:`, err.message);
        res.writeHead(500, {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache'
        });
        res.end(JSON.stringify({ error: err.message }));
      }
    });
    return;
  }

  // Health check
  if (urlPath === '/api/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', time: new Date().toISOString() }));
    return;
  }

  // Static File Serving
  let safePath = path.normalize(urlPath).replace(/^(\.\.[\/\\])+/, '');
  let filePath = path.join(PUBLIC_DIR, safePath);

  if (urlPath === '/dashboard' || urlPath === '/admin') {
    filePath = path.join(PUBLIC_DIR, 'dashboard.html');
  } else if (fs.existsSync(filePath) && fs.statSync(filePath).isDirectory()) {
    filePath = path.join(filePath, 'index.html');
  }

  if (!fs.existsSync(filePath)) {
    filePath = path.join(PUBLIC_DIR, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('500 Server Error');
      return;
    }
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(content);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`TCZ Local Web Server + API Bridge is running at http://localhost:${PORT}`);
});
