'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {setTimeout: pause} = require('node:timers/promises');
const root = path.resolve(__dirname, '..');
const target = 'https://stalwart-travesseiro-1e8045.netlify.app';
const hostname = new URL(target).hostname;
const sha256 = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

function assertTarget(site) {
  if (!site.id || site.name !== 'stalwart-travesseiro-1e8045') {
    throw Error('Target mismatch: refusing to publish to another Netlify site.');
  }
}

function loadPackage() {
  const metadata = JSON.parse(fs.readFileSync(path.join(root, '.qa/netlify-package.json'), 'utf8'));
  const zipPath = path.resolve(metadata.Zip);
  const relative = path.relative(path.join(root, '.qa'), zipPath);
  if (metadata.Target !== target || relative.startsWith('..') || path.isAbsolute(relative) || !zipPath.endsWith('.zip')) {
    throw Error('Invalid deployment package or target.');
  }
  const zip = fs.readFileSync(zipPath);
  if (zip.length !== metadata.ZipBytes || sha256(zip) !== metadata.ZipSha256 ||
      sha256(fs.readFileSync(path.join(root, 'site/main.dart.js'))) !== metadata.BundleHash) {
    throw Error('Package changed: rebuild the archive before publishing.');
  }
  return {metadata, zip};
}

function loadToken() {
  if (process.env.NETLIFY_AUTH_TOKEN?.trim()) return process.env.NETLIFY_AUTH_TOKEN.trim();
  const config = path.join(root, '.env.local');
  if (fs.existsSync(config)) {
    for (const line of fs.readFileSync(config, 'utf8').split(/\r?\n/)) {
      const match = line.match(/^\s*NETLIFY_AUTH_TOKEN\s*=\s*(.*?)\s*$/);
      if (match) {
        const token = match[1].replace(/^(['"])(.*)\1$/, '$2').trim();
        if (token) return token;
      }
    }
  }
  throw Error('NETLIFY_AUTH_TOKEN is missing. Add it to .env.local; never put it in chat.');
}

async function main() {
  const {metadata, zip} = loadPackage();
  if (process.argv.includes('--check-package')) {
    console.log(JSON.stringify({target, release: metadata.Release, files: metadata.Files,
      zipBytes: zip.length, bundleHash: metadata.BundleHash, packageVerified: true}));
    return;
  }
  const token = loadToken();
  async function api(route, options = {}) {
    const response = await fetch('https://api.netlify.com/api/v1' + route, {
      ...options, headers: {...options.headers, Authorization: 'Bearer ' + token},
      signal: AbortSignal.timeout(60000),
    });
    if (!response.ok) throw Error('Netlify API returned HTTP ' + response.status + '.');
    return response.json();
  }
  const site = await api('/sites/' + hostname);
  assertTarget(site);
  if (site.published_deploy?.locked) throw Error('The production deploy is locked in Netlify.');
  console.log('Verified target: ' + target);
  let deploy = await api('/sites/' + encodeURIComponent(site.id) + '/deploys?draft=false&title=' + encodeURIComponent(metadata.Release), {
    method: 'POST', headers: {'Content-Type': 'application/zip'}, body: zip,
  });
  if (!deploy.id) throw Error('Netlify did not return a deploy ID.');
  const deployId = deploy.id;
  console.log('Deploy submitted: ' + deployId);
  for (let attempt = 0; deploy.state !== 'ready' && attempt < 60; attempt++) {
    if (deploy.state === 'error') throw Error('Netlify reported a deployment error: ' + deployId);
    await pause(3000);
    deploy = await api('/deploys/' + encodeURIComponent(deployId));
    console.log('Deploy state: ' + deploy.state);
  }
  if (deploy.state !== 'ready') throw Error('Deploy is still processing. Check deploy ' + deployId + ' before retrying.');
  const receipt = {deployId, siteId: site.id, target, state: deploy.state, release: metadata.Release,
    bundleHash: metadata.BundleHash, verified: false, deployedAt: new Date().toISOString()};
  const receiptFile = path.join(root, '.qa/netlify-last-deploy.json');
  fs.writeFileSync(receiptFile, JSON.stringify(receipt, null, 2));
  for (let attempt = 0; attempt < 6; attempt++) {
    const versionResponse = await fetch(target + '/release.json?deploy=' + deployId, {signal: AbortSignal.timeout(30000)});
    const programResponse = await fetch(target + '/main.dart.js?deploy=' + deployId, {signal: AbortSignal.timeout(60000)});
    if (versionResponse.ok && programResponse.ok) {
      const release = await versionResponse.json();
      const program = Buffer.from(await programResponse.arrayBuffer());
      if (release.bundle_sha256 === metadata.BundleHash && sha256(program) === metadata.BundleHash) {
        receipt.verified = true;
        fs.writeFileSync(receiptFile, JSON.stringify(receipt, null, 2));
        console.log(JSON.stringify(receipt));
        return;
      }
    }
    await pause(3000);
  }
  throw Error('Deploy is ready, but the public bundle has not matched yet. Check ' + deployId + ' before retrying.');
}

module.exports = {assertTarget};
if (require.main === module) main().catch(error => {console.error(error.message); process.exitCode = 1;});
