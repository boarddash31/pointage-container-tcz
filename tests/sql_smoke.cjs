const {PGlite}=require('@electric-sql/pglite');const fs=require('node:fs');const assert=require('node:assert/strict');
(async()=>{const db=new PGlite();try{
await db.exec("create role anon; create role authenticated; create schema auth; create schema storage; create table auth.users(id uuid primary key,raw_user_meta_data jsonb); create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit integer,allowed_mime_types text[]); create table storage.objects(id uuid,bucket_id text);");
let sql=fs.readFileSync('supabase/migrations/202610190001_core.sql','utf8').replace('create extension if not exists pgcrypto;','');await db.exec(sql);await db.exec(fs.readFileSync('supabase/migrations/202610190002_reporting_admin.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/202610190003_forced_actions.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/202610190004_document_actions.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/202610190005_manual_containers.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/202610200002_optional_position.sql','utf8'));await db.exec(fs.readFileSync('supabase/seed.sql','utf8'));let n=await db.query('select count(*) as n from public.armateurs');assert.equal(Number(n.rows[0].n),95);
await db.exec('grant usage on schema auth to authenticated; grant execute on function auth.uid() to authenticated;');let checks=await db.query("select public.valid_container_number('CSQU3054383') ok, public.valid_container_number('CSQU3054384') bad");assert.equal(checks.rows[0].ok,true);assert.equal(checks.rows[0].bad,false);
const actor='11111111-1111-4111-8111-111111111111';await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[actor,JSON.stringify({name:'Test Admin'})]);await db.query('insert into public.user_roles(user_id,role) values($1,$2)',[actor,'admin']);await db.exec(`set request.jwt.claim.sub='${actor}'`);
let first=await db.query("select public.enter_truck('12345-A-06','AB123456','loaded','CSQU3054383',null,'45G1','MAE') id");const firstId=first.rows[0].id;assert.ok(firstId);let denied=false;
try{await db.query("select public.enter_truck('DUPLICATE','AB123456','loaded','CSQU3054383',null,'45G1','MAE')")}
catch(e){denied=/one_active_container_on_truck/.test(e.message)}assert.ok(denied,'same container cannot be on two active trucks');denied=false;
try{await db.query('select public.exit_truck($1)',[firstId])}catch(e){denied=/Engin must be completed/.test(e.message)}assert.ok(denied,'exit must require Engin');
await db.query("select public.perform_engin($1,null,null)",[firstId]);denied=false;try{await db.query("select public.perform_engin($1,null,null)",[firstId])}catch(e){denied=/visit unavailable/.test(e.message)}assert.ok(denied,'duplicate Engin must be denied');
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
await db.exec(fs.readFileSync('supabase/migrations/202610200003_allow_direct_exit.sql','utf8'));
await db.exec(`set request.jwt.claim.sub='${actor}'`);
const directCont = await db.query("select 'MSCU123456'||d::text as number from generate_series(0,9) d where public.valid_container_number('MSCU123456'||d::text) limit 1");
let directVisit = await db.query("select public.enter_truck('DIR-01','EF999999','loaded',$1,null,'45G1','MAE') id", [directCont.rows[0].number]);
const directId = directVisit.rows[0].id;
await db.query('select public.exit_truck($1)', [directId]);
let directRow = await db.query('select engin_at, exited_at from public.truck_visits where id=$1', [directId]);
assert.ok(directRow.rows[0].engin_at, 'direct exit should auto-set engin_at');
assert.ok(directRow.rows[0].exited_at, 'direct exit should set exited_at');
let directStock = await db.query('select count(*) n from public.container_stock_intervals where container_number=$1 and departed_at is null', [directCont.rows[0].number]);
await db.exec(fs.readFileSync('supabase/migrations/202610200004_twin_and_sortie_workflow.sql','utf8'));
const twinC1 = await db.query("select 'TWNA123456'||d::text as number from generate_series(0,9) d where public.valid_container_number('TWNA123456'||d::text) limit 1");
const twinC2 = await db.query("select 'TWNB654321'||d::text as number from generate_series(0,9) d where public.valid_container_number('TWNB654321'||d::text) limit 1");
let twinVisit = await db.query("select public.enter_truck('TWIN-01','TW999999','loaded',$1,null,'22G1','MAE',null,true,$2,'22G1','CMACGM') id",
  [twinC1.rows[0].number, twinC2.rows[0].number]);
assert.ok(twinVisit.rows[0].id, 'twin entry created');
await db.query('select public.exit_truck($1)', [twinVisit.rows[0].id]);
let twinRow = await db.query('select is_twin, container_number_2, exited_at from public.truck_visits where id=$1', [twinVisit.rows[0].id]);
assert.equal(twinRow.rows[0].is_twin, true);
assert.equal(twinRow.rows[0].container_number_2, twinC2.rows[0].number);
assert.ok(twinRow.rows[0].exited_at);

// Test empty truck that leaves empty without pickup (ki dkhal ki khraj)
let emptyVisit = await db.query("select public.enter_truck('EMP-01','EM111111','empty',null,'BK-EMPTY','22G1','MAE') id");
await db.query("select public.exit_truck_with_details($1,null,null,null,false,null,null,null,true)", [emptyVisit.rows[0].id]);
let emptyRow = await db.query('select canceled_at, cancel_reason from public.truck_visits where id=$1', [emptyVisit.rows[0].id]);
assert.ok(emptyRow.rows[0].canceled_at, 'empty exit without pickup should record cancel');

await db.exec('set role authenticated');let visible=await db.query('select count(*) n from public.armateurs');assert.equal(Number(visible.rows[0].n),95);denied=false;try{await db.query("insert into public.armateurs(id,name) values('BAD','BAD')")}catch(e){denied=true}assert.ok(denied,'client table write must be denied');
await db.exec('reset role');
await db.exec(fs.readFileSync('supabase/migrations/20261020155355_transaction_data.sql','utf8'));
await db.exec("set request.jwt.claim.sub='11111111-1111-4111-8111-111111111111'");
await db.query("update public.profiles set display_name='Entry Operator' where id=$1",[actor]);
const editor='44444444-4444-4444-8444-444444444444';
await db.query('insert into auth.users(id,raw_user_meta_data) values($1,$2)',[editor,JSON.stringify({name:'Exit Operator'})]);
await db.query("insert into public.user_roles(user_id,role) values($1,'sortie')",[editor]);
const beforeData=await db.query('select public.data_transactions() row');
const beforeTx=beforeData.rows.map(x=>x.row).find(x=>x.id===twinVisit.rows[0].id);
assert.equal(beforeTx.creator_name,'Entry Operator');
assert.equal(beforeTx.changer_name,'Entry Operator');
assert.ok(beforeTx.transaction_number);
await db.query("insert into public.audit_logs(entity,entity_id,action,actor_id) values('truck_visit',$1,'TEST_UPDATE',$2)",[twinVisit.rows[0].id,editor]);
await db.exec("set request.jwt.claim.sub='"+editor+"'");
await db.exec('set role authenticated');
const afterData=await db.query('select public.data_transactions() row');
const afterTx=afterData.rows.map(x=>x.row).find(x=>x.id===twinVisit.rows[0].id);
assert.equal(afterTx.creator_name,'Entry Operator','creator is preserved');
assert.equal(afterTx.changer_name,'Exit Operator','last changer follows audit');
assert.equal(afterTx.transaction_number,beforeTx.transaction_number,'transaction number is permanent');
const privateProfiles=await db.query('select count(*) n from public.profiles');
assert.equal(Number(privateProfiles.rows[0].n),1,'other profiles remain private outside transaction summary');
await db.exec('reset role');
await db.exec("set request.jwt.claim.sub='00000000-0000-0000-0000-000000000000'");
let noPermission=false;try{await db.query('select public.data_transactions()')}catch(e){noPermission=e.code==='42501'}
assert.ok(noPermission,'unassigned users cannot read transaction identities');
await db.exec('reset role');
await db.exec(fs.readFileSync('supabase/migrations/20261020162717_gate_out_iso_length_check.sql','utf8'));
await db.exec("set request.jwt.claim.sub='11111111-1111-4111-8111-111111111111'");
const iso20Visit=(await db.query("select public.enter_truck('ISO20','AB12345','empty',null,'BOOK20','22G1','MAE') id")).rows[0].id;
const snapshotIsoState=async()=>JSON.stringify((await db.query(`select
  (select to_jsonb(v) from public.truck_visits v where id='${iso20Visit}') as visit,
  (select jsonb_agg(to_jsonb(c) order by c.number) from public.containers c) as containers,
  (select jsonb_agg(to_jsonb(s) order by s.id) from public.container_stock_intervals s) as stock,
  (select count(*) from public.visit_events) as events,
  (select count(*) from public.audit_logs) as audit,
  (select count(*) from public.generated_documents) as documents`)).rows);
const isoBefore=await snapshotIsoState();
const expectIsoDenied=async(sql,args)=>{
  let error;try{await db.query(sql,args)}catch(e){error=e}
  assert.ok(error && error.code==='23514','size mismatch must be rejected, got '+error?.message);
};
await expectIsoDenied('select public.exit_truck_with_details($1,$2,$3)',[iso20Visit,directCont.rows[0].number,'45G1']);
await expectIsoDenied('select public.exit_truck_with_details($1,$2,$3)',[iso20Visit,directCont.rows[0].number,'22G1']);
await expectIsoDenied('select public.exit_truck($1)',[iso20Visit]);
assert.equal(await snapshotIsoState(),isoBefore,'failed exits leave visit, stock, master, audit and documents unchanged');
const iso40Visit=(await db.query("select public.enter_truck('ISO40','AB12345','empty',null,'BOOK40','45G1','MAE') id")).rows[0].id;
await expectIsoDenied('select public.exit_truck_with_details($1,$2,$3)',[iso40Visit,twinC1.rows[0].number,'22G1']);
await expectIsoDenied('select public.exit_truck_with_details($1,$2,$3)',[iso40Visit,twinC1.rows[0].number,'45G1']);
await expectIsoDenied('select public.exit_truck_with_details($1,$2,$3,null,true,$4,$5)',[iso20Visit,twinC1.rows[0].number,'22G1',directCont.rows[0].number,'22G1']);
await expectIsoDenied('select public.exit_truck_with_details($1,$2,$3,null,true,$4,$5)',[iso40Visit,directCont.rows[0].number,'45G1',twinC1.rows[0].number,'22G1']);
// Same length with a different height remains allowed: 42G1 and 45G1 are both 40-foot.
await db.query('select public.exit_truck_with_details($1,$2,$3)',[iso40Visit,directCont.rows[0].number,'42G1']);
assert.ok((await db.query('select exited_at from public.truck_visits where id=$1',[iso40Visit])).rows[0].exited_at);
// Both 20-foot containers succeed in twin mode.
await db.query('select public.exit_truck_with_details($1,$2,$3,null,true,$4,$5)',[iso20Visit,twinC1.rows[0].number,'22G1',twinC2.rows[0].number,'22G1']);
assert.ok((await db.query('select exited_at from public.truck_visits where id=$1',[iso20Visit])).rows[0].exited_at);
const isoCancel=(await db.query("select public.enter_truck('ISOCANCEL','AB12345','empty',null,'BOOKCANCEL','22G1','MAE') id")).rows[0].id;
await db.query('select public.exit_truck_with_details($1,null,null,null,false,null,null,null,true)',[isoCancel]);
assert.ok((await db.query('select canceled_at from public.truck_visits where id=$1',[isoCancel])).rows[0].canceled_at);
console.log('PASS: gate-out size mismatch both ways, spoofed ISO, second twin, missing pickup, atomic failures, same-length acceptance, valid twin and empty cancellation');

await require('./order_assignment.cjs')(db, actor, 'supabase/migrations/20261023114008_client_orders_and_carrier_bookings.sql', 'supabase/migrations/20261023120228_system_managed_client_orders.sql');
await require('./transport_rules.cjs')(db,actor,'supabase/migrations/20261023144404_transport_orders_and_24h_delivery.sql');
await require('./document_printing.cjs')(db,actor,'supabase/migrations/20261023151708_document_author_and_print_context.sql');
await require('./editable_orders.cjs')(db,actor,'supabase/migrations/20261026125117_editable_globally_unique_transport_orders.sql');
// The following migration only repairs French message encoding; PGlite lacks WIN1252 conversion.
// It is verified on ZENATA's PostgreSQL instead of this WASM runtime.
console.log('PASS: transaction number stability, creator, last changer, agent access, profile isolation and unauthorized denial');
console.log('PASS: migrations, 95 operators, checksum, lifecycle, stock, audit, documents, forced pickup/reconciliation, direct exit, twin 2-company, empty exit cancel, role denial and RLS role');
}catch(e){console.error('ERROR',e);process.exitCode=1}finally{await db.close()}})();



