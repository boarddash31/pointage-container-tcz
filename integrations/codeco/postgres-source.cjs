'use strict';
const fs=require('node:fs');
const {Client}=require('pg');
const {CodecoError}=require('./core.cjs');
class PostgresSource {
  constructor(connectionString,caFile){
    let uri;try{uri=new URL(connectionString);}catch{throw new CodecoError('invalid_source_connection');}
    const project='iparzfqxopcvwqelxlad';
    if(!['postgres:','postgresql:'].includes(uri.protocol)||
      !(uri.hostname==='db.'+project+'.supabase.co'||decodeURIComponent(uri.username).endsWith('.'+project))||
      [...uri.searchParams.keys()].some(k=>/^ssl/i.test(k)))throw new CodecoError('invalid_source_connection');
    const ssl={rejectUnauthorized:true};if(caFile)ssl.ca=fs.readFileSync(caFile,'utf8');
    this.options={connectionString,ssl,connectionTimeoutMillis:15000,application_name:'pointage-codeco-reader'};
  }
  async fetch(request){
    const client=new Client(this.options);
    try{
      await client.connect();
      await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
      await client.query("SET LOCAL statement_timeout='30s'");
      const result=await client.query('SELECT * FROM private.codeco_extract($1::timestamptz,$2::timestamptz)',[request.from.toISOString(),request.to.toISOString()]);
      await client.query('COMMIT');
      return result.rows.map(row=>({...row,occurred_at:row.occurred_at instanceof Date?row.occurred_at.toISOString():row.occurred_at}));
    }catch{try{await client.query('ROLLBACK');}catch{}throw new CodecoError('source_unavailable');}
    finally{await client.end().catch(()=>{});}
  }
}
module.exports={PostgresSource};
