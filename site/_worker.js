/**
 * Cloudflare Pages / Workers Advanced Worker
 * Proxies /api/rpc/* to Supabase to bypass corporate network inspection (Marsa Maroc 416 block)
 * and serves static site assets for all other routes.
 */

const SUPABASE_URL = 'https://iparzfqxopcvwqelxlad.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlwYXJ6ZnF4b3BjdndxZWx4bGFkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI0MTE3MjMsImV4cCI6MjEwNzk4NzcyM30.3hCnAHLQ8KRNRmaXCAMO8POWIRrjdeqMtqs8EavIbBs';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, apikey, Authorization'
        }
      });
    }

    // 1. API RPC Reverse Proxy (Bypasses corporate firewall blocks for marsa.digital)
    if (url.pathname.startsWith('/api/rpc/')) {
      const fnName = url.pathname.replace('/api/rpc/', '');
      const targetUrl = `${SUPABASE_URL}/rest/v1/rpc/${fnName}${url.search}`;

      const body = (request.method === 'POST' || request.method === 'PUT' || request.method === 'PATCH')
        ? await request.text()
        : null;

      try {
        const originRes = await fetch(targetUrl, {
          method: request.method,
          headers: {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
            'Content-Type': 'application/json'
          },
          body
        });

        const resHeaders = new Headers(originRes.headers);
        resHeaders.set('Access-Control-Allow-Origin', '*');
        resHeaders.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        resHeaders.set('Access-Control-Allow-Headers', 'Content-Type, apikey, Authorization');
        resHeaders.set('Cache-Control', 'no-cache, no-store, must-revalidate');

        return new Response(originRes.body, {
          status: originRes.status,
          statusText: originRes.statusText,
          headers: resHeaders
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), {
          status: 502,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          }
        });
      }
    }

    // 2. Health check
    if (url.pathname === '/api/health') {
      return new Response(JSON.stringify({ status: 'ok', provider: 'cloudflare', time: new Date().toISOString() }), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      });
    }

    // Explicitly retire the APK/checksum links from the previous mobile release.
    if (url.pathname.startsWith('/downloads/')) {
      return new Response('Not found', {
        status: 404,
        headers: { 'Cache-Control': 'no-store' }
      });
    }

    // 3. Fallback to static assets
    if (env && env.ASSETS) {
      if (url.pathname === '/dashboard' || url.pathname === '/admin') {
        const dashboardUrl = new URL('/dashboard.html', request.url);
        return env.ASSETS.fetch(new Request(dashboardUrl, request));
      }
      return env.ASSETS.fetch(request);
    }

    return fetch(request);
  }
};
