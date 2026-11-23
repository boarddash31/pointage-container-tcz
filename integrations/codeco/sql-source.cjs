'use strict';
const {SqlSource}=require('../reports/sql-source.cjs');
const {CodecoError}=require('./core.cjs');
class SqlCodecoSource extends SqlSource{
 async fetch(request){try{return await super.fetch(request);}catch{throw new CodecoError('source_unavailable');}}
}
module.exports={SqlCodecoSource};
