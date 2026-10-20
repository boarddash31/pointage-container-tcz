import http from 'node:http';
import https from 'node:https';
import {readFile, stat, mkdir, open, unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KINDS = new Set(['ENTREE', 'DEPOSE', 'PRISE', 'SORTIE']);
const MAX_PDF = 10_000_000;
class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const reply = (response, status, body, corsOrigin) => {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    ...(corsOrigin ? {'access-control-allow-origin': corsOrigin, 'vary': 'Origin'} : {}),
  });
  response.end(JSON.stringify(body));
};
async function readJson(request) {
  let body = '';
  for await (const part of request) {
    body += part.toString('utf8');
    if (body.length > 1024) throw new HttpError(413, 'Request too large');
  }
  try { return JSON.parse(body); }
  catch { throw new HttpError(400, 'Invalid JSON'); }
}
async function upstream(fetcher, url, headers, init = {}) {
  const response = await fetcher(url, {...init, headers, signal: AbortSignal.timeout(15000)});
  if (!response.ok) throw new HttpError(response.status === 401 ? 401 : 502, 'Supabase request failed');
  return response;
}
async function saveOnce(folder, name, pdf) {
  const path = join(folder, name);
  try {
    const handle = await open(path, 'wx');
    try { await handle.writeFile(pdf); }
    catch (error) { await handle.close(); await unlink(path).catch(() => {}); throw error; }
    await handle.close();
    return {path, existed: false};
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const old = await readFile(path);
    const digest = bytes => createHash('sha256').update(bytes).digest('hex');
    if (digest(old) !== digest(pdf)) throw new HttpError(409, 'Archived file differs from Supabase');
    return {path, existed: true};
  }
}
export async function sumatraPrint(executable, printer, path) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, ['-silent', '-print-to', printer, path],
      {shell: false, windowsHide: true, stdio: 'ignore'});
    const timer = setTimeout(() => child.kill(), 60000);
    child.once('error', error => { clearTimeout(timer); reject(error); });
    child.once('exit', code => {
      clearTimeout(timer);
      code === 0 ? resolve() : reject(new Error(`PDF print command exited ${code}`));
    });
  });
}
export function createBridgeHandler(config, {fetcher = fetch, printer = sumatraPrint} = {}) {
  const base = config.supabaseUrl.replace(/\/$/, '');
  const allowed = new Set(config.allowedOrigins ?? []);
  return async (request, response) => {
    const origin = request.headers.origin;
    const corsOrigin = origin && allowed.has(origin) ? origin : undefined;
    try {
      if (origin && !corsOrigin) throw new HttpError(403, 'Origin not allowed');
      if (request.method === 'OPTIONS') {
        response.writeHead(204, {
          'access-control-allow-origin': corsOrigin ?? '',
          'access-control-allow-methods': 'POST, OPTIONS',
          'access-control-allow-headers': 'authorization, content-type',
          'vary': 'Origin',
        }); response.end(); return;
      }
      if (request.url !== '/api/documents/archive' || request.method !== 'POST')
        throw new HttpError(404, 'Endpoint unavailable');
      const authorization = request.headers.authorization ?? '';
      if (!/^Bearer [A-Za-z0-9._-]{20,8000}$/.test(authorization))
        throw new HttpError(401, 'Supabase session required');
      const input = await readJson(request);
      if (!UUID.test(input?.document_id) || typeof input?.print !== 'boolean')
        throw new HttpError(400, 'document_id and print are required');
      if (input.print && (!config.sumatraPath || !config.printerName))
        throw new HttpError(503, 'Direct printer not configured');
      const headers = {apikey: config.publishableKey, authorization};
      await upstream(fetcher, `${base}/auth/v1/user`, headers);
      const query = new URL(`${base}/rest/v1/generated_documents`);
      query.searchParams.set('id', `eq.${input.document_id}`);
      query.searchParams.set('select', 'id,visit_id,kind,status,storage_path');
      const rows = await (await upstream(fetcher, query, headers)).json();
      const document = rows?.[0];
      if (!document || document.id !== input.document_id ||
          !UUID.test(document.visit_id) || !KINDS.has(document.kind) ||
          document.status !== 'uploaded' ||
          document.storage_path !== `${document.visit_id}/${document.id}.pdf`)
        throw new HttpError(404, 'Document unavailable');
      const audit = action => upstream(fetcher,
        `${base}/rest/v1/rpc/record_document_action`,
        {...headers, 'content-type': 'application/json'},
        {method: 'POST', body: JSON.stringify({p_document: document.id, p_action: action})});
      await audit('BRIDGE_ARCHIVE_REQUESTED');
      if (input.print) await audit('BRIDGE_PRINT_REQUESTED');
      const objectPath = document.storage_path.split('/').map(encodeURIComponent).join('/');
      const downloaded = await upstream(fetcher,
        `${base}/storage/v1/object/authenticated/pointage-documents/${objectPath}`, headers);
      if (Number(downloaded.headers.get('content-length') ?? 0) > MAX_PDF)
        throw new HttpError(413, 'PDF exceeds size limit');
      const pdf = Buffer.from(await downloaded.arrayBuffer());
      if (pdf.length < 8 || pdf.length > MAX_PDF || !pdf.subarray(0, 5).equals(Buffer.from('%PDF-')))
        throw new HttpError(422, 'Invalid PDF');
      const archiveName = `TCZ_${document.kind}_${document.visit_id}_${document.id}.pdf`;
      const saved = await saveOnce(config.sharePath, archiveName, pdf);
      let printStatus = 'not_requested';
      if (input.print) {
        await mkdir(config.statePath, {recursive: true});
        const marker = join(config.statePath, `${document.id}.print-requested`);
        try {
          const lock = await open(marker, 'wx');
          await lock.writeFile(JSON.stringify({document_id: document.id, printer: config.printerName,
            requested_at: new Date().toISOString()}));
          await lock.close();
          await printer(config.sumatraPath, config.printerName, saved.path);
          printStatus = 'submitted_to_printer';
        } catch (error) {
          if (error.code === 'EEXIST') printStatus = 'already_requested';
          else throw new HttpError(502, 'Print request failed; check bridge log and marker before retry');
        }
      }
      reply(response, 200, {document_id: document.id, archive_name: archiveName,
        already_archived: saved.existed, print_status: printStatus}, corsOrigin);
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('Bridge error:', error);
      reply(response, error.status ?? 500, {error: error instanceof HttpError ? error.message : 'Bridge unavailable'}, corsOrigin);
    }
  };
}
export async function startFromEnvironment(env = process.env) {
  const host = env.BRIDGE_HOST ?? '127.0.0.1';
  const port = Number(env.BRIDGE_PORT ?? '8848');
  const sharePath = env.PDF_SHARE_PATH;
  const supabaseUrl = env.SUPABASE_URL;
  const publishableKey = env.SUPABASE_PUBLISHABLE_KEY;
  if (!sharePath || !supabaseUrl || !publishableKey || !Number.isInteger(port) || port < 1 || port > 65535)
    throw new Error('PDF_SHARE_PATH, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY and valid BRIDGE_PORT required');
  if (!/^https:\/\//.test(supabaseUrl)) throw new Error('Supabase URL must use HTTPS');
  if (!(await stat(sharePath)).isDirectory()) throw new Error('PDF_SHARE_PATH must be an existing directory');
  const tls = !!env.BRIDGE_TLS_CERT && !!env.BRIDGE_TLS_KEY;
  if (!tls && !['127.0.0.1', '::1', 'localhost'].includes(host))
    throw new Error('LAN binding requires BRIDGE_TLS_CERT and BRIDGE_TLS_KEY');
  const config = {supabaseUrl, publishableKey, sharePath,
    statePath: env.BRIDGE_STATE_PATH ?? join(process.cwd(), '.state'),
    allowedOrigins: (env.BRIDGE_ALLOWED_ORIGINS ?? '').split(',').map(x => x.trim()).filter(Boolean),
    sumatraPath: env.SUMATRA_PDF_PATH, printerName: env.PDF_PRINTER_NAME};
  const handler = createBridgeHandler(config);
  const server = tls ? https.createServer({key: await readFile(env.BRIDGE_TLS_KEY),
    cert: await readFile(env.BRIDGE_TLS_CERT)}, handler) : http.createServer(handler);
  await new Promise(resolve => server.listen(port, host, resolve));
  console.log(`Pointage PDF bridge listening on ${tls ? 'https' : 'http'}://${host}:${port}`);
  return server;
}
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  startFromEnvironment().catch(error => { console.error(error.message); process.exitCode = 1; });
}
