import assert from 'node:assert/strict';
import { gateOutValues } from '../supabase/functions/generate-bon/gate-out-values.ts';

const document = {
  id: 'doc-123', event_id: 227653, created_at: '2026-10-27T13:09:01Z',
  print_context: {created_at_local: '2026-10-27 14:09:01', agent_name: 'Renamed agent'},
  snapshot: {entry_kind: 'empty', plate: '33674-A-7', driver_cin: 'H783343',
    agent_name: 'Archived agent', container_number: 'UETU8580329', iso_code: '45G1', armateur_id: 'MSC',
    carrier_booking_reference: 'EDO-2026-001',
    exit_document: {load_status: 'MTY', gross_weight_kg: 3900}},
};
const slip=gateOutValues(document);
assert.equal(slip.reference,'227653');
assert.equal(slip.date,'2026-10-27 14:09:01');
assert.equal(slip.agent,'Archived agent');
assert.equal(slip.containers[0].status,'Vide');
assert.equal(slip.containers[0].weight,'3900');
assert.equal(slip.fields.declaration_number,'');
assert.equal(slip.fields.bill_of_lading,'');
assert.deepEqual(slip.orders,['EDO-2026-001']);
const receiving=gateOutValues({...document,snapshot:{...document.snapshot,entry_kind:'loaded'}});
assert.equal(receiving.emptyChassis,true);
assert.deepEqual(receiving.containers,[]);
const twin=gateOutValues({...document,snapshot:{...document.snapshot,is_twin:true,
  iso_code:'22G1',container_number_2:'CSQU3054383',iso_code_2:'22G1',armateur_id_2:'MAE',exit_document:{}}});
assert.equal(twin.containers.length,2);
assert.deepEqual(twin.containers.map(c=>c.status),['','']);
assert.deepEqual(twin.containers.map(c=>c.weight),['','']);
assert.equal(twin.containers[1].number,'CSQU3054383');
const utc=gateOutValues({...document,print_context:{},event_id:null});
assert.equal(utc.date,'2026-10-27 13:09:01 UTC');
assert.equal(utc.reference,'doc-123');
console.log('PASS: archived exit values, empty chassis, twin containers, explicit cargo facts, UTC and references');
