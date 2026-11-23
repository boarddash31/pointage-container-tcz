const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const source=fs.readFileSync('app/web/flutter_bootstrap.js','utf8').replace('{{flutter_js}}','').replace('{{flutter_build_config}}','');
const release=source.match(/const release = '([^']+)'/)[1];
(async()=>{
  const events=[];
  const context={window:{},document:{baseURI:'http://localhost:8787/marsa-bons-v1/'},URL,console,
    navigator:{serviceWorker:{getRegistrations:async()=>[
      {scope:'http://localhost:8787/',active:{scriptURL:'http://localhost:8787/flutter_service_worker.js'},unregister:async()=>{await Promise.resolve();events.push('unregister');}},
      {scope:'http://localhost:8787/other/',active:{scriptURL:'http://localhost:8787/other/flutter_service_worker.js'},unregister:()=>{throw Error('Unrelated worker removed');}},
    ]}},caches:{keys:async()=>['flutter-app-cache','unrelated-cache'],delete:async key=>{await Promise.resolve();events.push('delete:'+key);}},
    _flutter:{buildConfig:{builds:[{mainJsPath:'main.dart.js'}]},loader:{load:()=>events.push('load')}}};
  context.window.caches=context.caches;
  vm.runInNewContext(source,context);await context.window.tczBootReady;
  assert.deepEqual(events,['unregister','delete:flutter-app-cache','load']);
  assert.equal(context._flutter.buildConfig.builds[0].mainJsPath,'main.dart.js?tcz_release='+release);
  assert.ok(fs.readFileSync('app/web/index.html','utf8').includes('flutter_bootstrap.js?tcz_release='+release));
  const unavailable={window:{},navigator:{},document:{baseURI:'http://localhost:8787/'},console,
    _flutter:{buildConfig:{builds:[]},loader:{load:()=>true}}};
  vm.runInNewContext(source,unavailable);assert.equal(await unavailable.window.tczBootReady,true);
  console.log('PASS: old Flutter cache removed before loading; unrelated workers/cache retained; fresh program URL; unsupported APIs tolerated');
})().catch(e=>{console.error(e);process.exitCode=1});
