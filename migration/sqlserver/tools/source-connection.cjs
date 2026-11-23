'use strict';
function validateSourceUrl(url,project){
 const direct=url.hostname==='db.'+project+'.supabase.co';
 const pooler=url.hostname.endsWith('.pooler.supabase.com')&&decodeURIComponent(url.username).endsWith('.'+project);
 if(!['postgres:','postgresql:'].includes(url.protocol)||(!direct&&!pooler)||!['','5432'].includes(url.port)||url.pathname!=='/postgres')
  throw Error('Use the authorized Supabase project direct/session-pooler endpoint on5432/database postgres.');
}
module.exports={validateSourceUrl};
