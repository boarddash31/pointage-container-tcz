import { createClient } from 'npm:@supabase/supabase-js@2.76.1';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
};
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, 'content-type': 'application/json' },
});
const validRoles = new Set(['admin', 'entree', 'engin', 'sortie', 'viewer']);

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return json(405, { error: 'POST required' });
  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ?? '';
  if (!token) return json(401, { error: 'Authentication required' });

  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anon || !service) return json(503, { error: 'Service configuration unavailable' });
  const caller = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: identity, error: identityError } = await caller.auth.getUser(token);
  if (identityError || !identity.user) return json(401, { error: 'Invalid session' });
  const { data: allowed, error: roleError } = await caller.rpc('can_do', { p_permission: 'admin' });
  if (roleError || allowed !== true) return json(403, { error: 'Admin role required' });

  let email: string;
  let name: string;
  let role: string;
  try {
    const body = await request.json();
    email = String(body.email ?? '').trim().toLowerCase();
    name = String(body.name ?? '').trim();
    role = String(body.role ?? '').trim().toLowerCase();
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        name.length > 120 || !validRoles.has(role)) throw Error('Invalid invitation fields');
  } catch {
    return json(400, { error: 'Valid email, name and role required' });
  }

  const admin = createClient(url, service, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: invitation, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { name, must_set_password: true },
  });
  if (inviteError || !invitation.user) return json(409, { error: inviteError?.message ?? 'Invitation failed' });
  const userId = invitation.user.id;
  const { error: roleInsertError } = await admin.from('user_roles').upsert({
    user_id: userId, role,
  }, { onConflict: 'user_id,role' });
  if (roleInsertError) {
    // The invitation may already be delivered. Do not hide a partially created account.
    return json(500, { error: 'Account invited but role assignment failed', user_id: userId });
  }
  const { error: auditError } = await admin.from('audit_logs').insert({
    entity: 'auth_user', entity_id: userId, action: 'INVITE_USER',
    actor_id: identity.user.id,
    after_data: { email, name, role },
  });
  if (auditError) return json(500, { error: 'Account invited with role but audit failed', user_id: userId });
  return json(200, { user_id: userId, role, invited: true });
});
