const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const source=fs.readFileSync('app/web/flutter_bootstrap.js','utf8').replace('{{flutter_js}}','').replace('{{flutter_build_config}}','');
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
  assert.match(context._flutter.buildConfig.builds[0].mainJsPath,/tcz_release=marsa-bons-v1/);
  const unavailable={window:{},navigator:{},document:{baseURI:'http://localhost:8787/'},console,
    _flutter:{buildConfig:{builds:[]},loader:{load:()=>true}}};
  vm.runInNewContext(source,unavailable);assert.equal(await unavailable.window.tczBootReady,true);
  console.log('PASS: old Flutter cache removed before loading; unrelated workers/cache retained; fresh program URL; unsupported APIs tolerated');
})().catch(e=>{console.error(e);process.exitCode=1});
