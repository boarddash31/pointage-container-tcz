import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createBridgeHandler, startFromEnvironment} from '../server.mjs';

const documentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const visitId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const token = 'Bearer valid-test-token-012345678901234567890';
const hiddenToken = 'Bearer valid-but-no-document-012345678901234';
const listen = async server => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return `http://127.0.0.1:${server.address().port}`;
};
const close = server => new Promise(resolve => server.close(resolve));

test('bridge verifies Supabase session and RLS before archiving and printing once', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'pointage-bridge-test-'));
  const pdf = Buffer.from('%PDF-1.4\nfixture PDF\n%%EOF');
  let prints = 0;
  const upstream = http.createServer((request, response) => {
    if (![token, hiddenToken].includes(request.headers.authorization) ||
        request.headers.apikey !== 'publishable-test') {
      response.writeHead(401).end(); return;
    }
    if (request.url === '/auth/v1/user') {
      response.writeHead(200, {'content-type': 'application/json'}).end('{"id":"user-id"}'); return;
    }
    if (request.url.startsWith('/rest/v1/generated_documents?')) {
      if (request.headers.authorization === hiddenToken) {
        response.writeHead(200, {'content-type': 'application/json'}).end('[]'); return;
      }
      response.writeHead(200, {'content-type': 'application/json'}).end(JSON.stringify([{
        id: documentId, visit_id: visitId, kind: 'ENTREE', status: 'uploaded',
        storage_path: `${visitId}/${documentId}.pdf`,
      }])); return;
    }
    if (request.url === '/rest/v1/rpc/record_document_action' && request.method === 'POST') {
      response.writeHead(204).end(); return;
    }
    if (request.url === `/storage/v1/object/authenticated/pointage-documents/${visitId}/${documentId}.pdf`) {
      response.writeHead(200, {'content-type': 'application/pdf'}).end(pdf); return;
    }
    response.writeHead(404).end();
  });
  const upstreamUrl = await listen(upstream);
  const bridge = http.createServer(createBridgeHandler({
    supabaseUrl: upstreamUrl, publishableKey: 'publishable-test',
    sharePath: folder, statePath: join(folder, 'state'),
    allowedOrigins: ['https://pointage.example'],
    sumatraPath: 'fake-sumatra.exe', printerName: 'TCZ Printer',
  }, {printer: async () => { prints++; }}));
  const bridgeUrl = await listen(bridge);
  const post = (body, headers = {}) => fetch(`${bridgeUrl}/api/documents/archive`, {
    method: 'POST', headers: {'content-type': 'application/json', ...headers},
    body: JSON.stringify(body),
  });
  try {
    const request = {document_id: documentId, print: false};
    assert.equal((await post(request)).status, 401);
    assert.equal((await post(request, {authorization: token, origin: 'https://evil.example'})).status, 403);
    assert.equal((await post(request, {authorization: hiddenToken})).status, 404);
    const first = await post(request, {authorization: token});
    assert.equal(first.status, 200);
    assert.equal((await first.json()).already_archived, false);
    const name = `TCZ_ENTREE_${visitId}_${documentId}.pdf`;
    assert.deepEqual(await readFile(join(folder, name)), pdf);
    const second = await post(request, {authorization: token});
    assert.equal((await second.json()).already_archived, true);
    const printed = await post({...request, print: true}, {authorization: token});
    assert.equal((await printed.json()).print_status, 'submitted_to_printer');
    const retry = await post({...request, print: true}, {authorization: token});
    assert.equal((await retry.json()).print_status, 'already_requested');
    assert.equal(prints, 1);
  } finally {
    await close(bridge); await close(upstream);
    await rm(folder, {recursive: true, force: true});
  }
});

test('LAN listener refuses to start without TLS', async () => {
  const folder = await mkdtemp(join(tmpdir(), 'pointage-bridge-tls-test-'));
  try {
    await assert.rejects(startFromEnvironment({
      PDF_SHARE_PATH: folder,
      SUPABASE_URL: 'https://example.supabase.co',
      SUPABASE_PUBLISHABLE_KEY: 'publishable-test',
      BRIDGE_HOST: '0.0.0.0', BRIDGE_PORT: '8848',
    }), /LAN binding requires/);
  } finally { await rm(folder, {recursive: true, force: true}); }
});
