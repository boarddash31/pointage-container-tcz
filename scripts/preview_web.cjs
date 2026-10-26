// Versioned local route bypasses a previous Flutter worker's cached root document.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../app/build/web');
const prefix = '/marsa-bons-v1/';
const mime = {'.html':'text/html; charset=utf-8','.js':'application/javascript',
  '.json':'application/json','.css':'text/css','.wasm':'application/wasm',
  '.png':'image/png','.svg':'image/svg+xml','.ttf':'font/ttf',
  '.woff2':'font/woff2','.ico':'image/x-icon','.pdf':'application/pdf'};
http.createServer((req,res) => {
  let route,file;
  try {
    route=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    if(route==='/'||route===prefix.slice(0,-1)){
      res.writeHead(302,{'Location':prefix,'Cache-Control':'no-store'}).end();return;
    }
    const relative=route.startsWith(prefix)?route.slice(prefix.length):route.slice(1);
    file=path.resolve(root,relative||'index.html');
  }catch{res.writeHead(400).end();return;}
  if(file!==root&&!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
  if(fs.existsSync(file)&&fs.statSync(file).isDirectory())file=path.join(file,'index.html');
  if(!fs.existsSync(file)){res.writeHead(404).end();return;}
  res.writeHead(200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store'});
  if(path.basename(file)==='index.html'&&route.startsWith(prefix)){
    res.end(fs.readFileSync(file,'utf8').replace('<base href="/">',`<base href="${prefix}">`));return;
  }
  fs.createReadStream(file).pipe(res);
}).listen(8787,'127.0.0.1',()=>console.log(`TCZ preview: http://localhost:8787${prefix}`));
