import assert from 'node:assert/strict';
import {hasCurrentPdf,documentPdfPath} from '../supabase/functions/generate-bon/pdf-cache.ts';
const archived={id:'doc',visit_id:'visit',kind:'ENTREE',status:'uploaded',storage_path:'visit/doc.pdf'};
assert.equal(hasCurrentPdf(archived),false,'an archived TCZ PDF must be regenerated in the requested format');
assert.equal(documentPdfPath(archived),'visit/doc-marsa-v1.pdf','new format has its own immutable file');
assert.equal(hasCurrentPdf({...archived,storage_path:'visit/doc-marsa-v1.pdf'}),true);
assert.equal(hasCurrentPdf({...archived,kind:'ANNULATION'}),true);
console.log('PASS: archived old layout is not reused; matching current layout is cached; cancellation archives preserved');
