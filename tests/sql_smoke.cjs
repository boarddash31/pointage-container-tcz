const {PGlite}=require('@electric-sql/pglite');const fs=require('node:fs');const assert=require('node:assert/strict');
(async()=>{const db=new PGlite();try{
await db.exec("create role anon; create role authenticated; create schema auth; create schema storage; create table auth.users(id uuid primary key,raw_user_meta_data jsonb); create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit integer,allowed_mime_types text[]); create table storage.objects(id uuid,bucket_id text);");
let sql=fs.readFileSync('supabase/migrations/202610190001_core.sql','utf8').replace('create extension if not exists pgcrypto;','');await db.exec(sql);await db.exec(fs.readFileSync('supabase/migrations/202610190002_reporting_admin.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/202610190003_forced_actions.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/202610190004_document_actions.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/202610190005_manual_containers.sql','utf8'));await db.exec(fs.readFileSync('supabase/seed.sql','utf8'));let n=await db.query('select count(*) as n from public.armateurs');assert.equal(Number(n.rows[0].n),95);
await db.exec('grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;');let checks=await db.query("select public.valid_container_number('CSQU3054383') ok, public.valid_container_number('CSQU3054384') bad");assert.equal(checks.rows[0].ok,true);assert.equal(checks.rows[0].bad,false);
const actor='11111111-1111-4111-8111-111111111111';await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[actor,JSON.stringify({name:'Test Admin'})]);await db.query('insert into public.user_roles(user_id,role) values($1,$2)',[actor,'admin']);await db.exec(`set request.jwt.claim.sub='${actor}'`);
let first=await db.query("select public.enter_truck('12345-A-06','AB123456','loaded','CSQU3054383',null,'45G1','MAE') id");const firstId=first.rows[0].id;assert.ok(firstId);let denied=false;
try{await db.query("select public.enter_truck('DUPLICATE','AB123456','loaded','CSQU3054383',null,'45G1','MAE')")}
catch(e){denied=/one_active_container_on_truck/.test(e.message)}assert.ok(denied,'same container cannot be on two active trucks');denied=false;
try{await db.query('select public.exit_truck($1)',[firstId])}catch(e){denied=/Engin must be completed/.test(e.message)}assert.ok(denied,'exit must require Engin');
await db.query("select public.perform_engin($1,null,'A-01-01-1')",[firstId]);denied=false;try{await db.query("select public.perform_engin($1,null,'A-01-01-1')",[firstId])}catch(e){denied=/visit unavailable/.test(e.message)}assert.ok(denied,'duplicate Engin must be denied');
let opened=await db.query('select count(*) n from public.container_stock_intervals where departed_at is null');assert.equal(Number(opened.rows[0].n),1);
await db.query('select public.exit_truck($1)',[firstId]);opened=await db.query('select count(*) n from public.container_stock_intervals where departed_at is null');assert.equal(Number(opened.rows[0].n),1);
let second=await db.query("select public.enter_truck('67890-B-06','CD123456','empty',null,'FREE-BOOKING/123','45G1','MAE') id");const secondId=second.rows[0].id;await db.query("select public.perform_engin($1,'CSQU3054383',null)",[secondId]);await db.query('select public.exit_truck($1)',[secondId]);opened=await db.query('select count(*) n from public.container_stock_intervals where departed_at is null');assert.equal(Number(opened.rows[0].n),0);
let activity=await db.query('select count(*) n from public.hourly_activity(current_date)');assert.equal(Number(activity.rows[0].n),72);let report=await db.query('select category,evp from public.freepool_rows(current_date,null,true)');assert.equal(report.rows[0].category,'40 DV HC');assert.equal(Number(report.rows[0].evp),2);let events=await db.query('select action from public.visit_events order by id');assert.deepEqual(events.rows.map(x=>x.action),['ENTREE','DEPOSE','SORTIE','ENTREE','PRISE','SORTIE']);
let audits=await db.query('select count(*) n from public.audit_logs');assert.equal(Number(audits.rows[0].n),6);
let docs=await db.query('select count(*) n from public.generated_documents');assert.equal(Number(docs.rows[0].n),6);
const document=await db.query('select id from public.generated_documents order by created_at limit 1');
await db.query("select public.record_document_action($1,'PRINT_DIALOG_REQUESTED')",[document.rows[0].id]);
await db.query("select public.record_document_action($1,'BRIDGE_ARCHIVE_REQUESTED')",[document.rows[0].id]);
await db.query("select public.record_document_action($1,'BRIDGE_PRINT_REQUESTED')",[document.rows[0].id]);
let documentActions=await db.query('select count(*) n from public.document_actions');assert.equal(Number(documentActions.rows[0].n),3);
const observed=await db.query("select 'DEFU654321'||d::text as number from generate_series(0,9) d where public.valid_container_number('DEFU654321'||d::text) limit 1");
await db.query('select public.register_observed_container($1,$2,$3)',[observed.rows[0].number,'42G1','MAE']);
let observedRow=await db.query('select source from public.containers where number=$1',[observed.rows[0].number]);assert.equal(observedRow.rows[0].source,'manual');
opened=await db.query('select count(*) n from public.container_stock_intervals where departed_at is null');assert.equal(Number(opened.rows[0].n),0);
const generated=await db.query("select 'ABCU123456'||d::text as number from generate_series(0,9) d where public.valid_container_number('ABCU123456'||d::text) limit 1");
const manualNumber=generated.rows[0].number;
const forcedVisit=await db.query("select public.enter_truck('FORCE-01','ZX12345','empty',null,'BOOK-FORCE','22G1','MAE') id");
let forced=await db.query('select public.force_pickup_without_stock($1,$2,$3) id',
  [forcedVisit.rows[0].id,manualNumber,'Conteneur present physiquement, absent du stock']);
let forcedId=forced.rows[0].id;assert.ok(forcedId);
denied=false;try{await db.query('select public.enter_truck($1,$2,$3,$4,$5,$6,$7)',
  ['DUP-FORCE','ZX12345','loaded',manualNumber,null,'22G1','MAE'])}
catch(e){denied=/one_active_container_on_truck/.test(e.message)}assert.ok(denied,'forced pickup container cannot be on a second active truck');
let manual=await db.query('select source from public.containers where number=$1',[manualNumber]);assert.equal(manual.rows[0].source,'manual');
opened=await db.query('select count(*) n from public.container_stock_intervals where departed_at is null');assert.equal(Number(opened.rows[0].n),0);
let forcedEvent=await db.query("select details->>'forced' as forced from public.visit_events where visit_id=$1 and action='PRISE'",[forcedVisit.rows[0].id]);assert.equal(forcedEvent.rows[0].forced,'true');
await db.query('select public.resolve_forced_action($1,$2)',[forcedId,'EXT-REC-001']);
let resolved=await db.query('select external_reference,resolved_at from public.forced_container_actions where id=$1',[forcedId]);assert.equal(resolved.rows[0].external_reference,'EXT-REC-001');assert.ok(resolved.rows[0].resolved_at);
const viewer='22222222-2222-4222-8222-222222222222';await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[viewer,'{}']);await db.query('insert into public.user_roles(user_id,role) values($1,$2)',[viewer,'viewer']);await db.exec(`set request.jwt.claim.sub='${viewer}'`);denied=false;
try{await db.query("select public.enter_truck('9876','EF12345','empty',null,'BK','45G1','MAE')")}catch(e){denied=/permission denied/.test(e.message)}assert.ok(denied,'viewer must not mutate');
denied=false;try{await db.query('select public.resolve_forced_action($1,$2)',[forcedId,'FORBIDDEN'])}catch(e){denied=/admin required/.test(e.message)}assert.ok(denied,'viewer must not reconcile forced actions');
denied=false;try{await db.query('select public.register_observed_container($1,$2,$3)',[observed.rows[0].number,'42G1','MAE'])}
catch(e){denied=/admin required/.test(e.message)}assert.ok(denied,'viewer must not register containers');
await db.exec('set role authenticated');let visible=await db.query('select count(*) n from public.armateurs');assert.equal(Number(visible.rows[0].n),95);denied=false;try{await db.query("insert into public.armateurs(id,name) values('BAD','BAD')")}catch(e){denied=true}assert.ok(denied,'client table write must be denied');console.log('PASS: migrations, 95 operators, checksum, lifecycle, stock, audit, documents, forced pickup/reconciliation, role denial and RLS role');
}catch(e){console.error('ERROR',e);process.exitCode=1}finally{await db.close()}})();



