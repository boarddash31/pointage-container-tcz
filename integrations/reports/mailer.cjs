'use strict';
const {ReportsError}=require('./calendar.cjs');
function createMailer(injected){
 let driver=injected;try{driver??=require('nodemailer');}catch{}
 function transport(c){if(!driver)throw new ReportsError('smtp_driver_unavailable',503);
  return driver.createTransport({host:c.host,port:c.port,secure:c.security==='tls',requireTLS:c.security==='starttls',ignoreTLS:c.security==='relay',
   ...(c.username?{auth:{user:c.username,pass:c.password}}:{}),tls:{rejectUnauthorized:true},
   connectionTimeout:15000,greetingTimeout:15000,socketTimeout:45000,logger:false,debug:false,
   disableFileAccess:true,disableUrlAccess:true});
 }
 return {available:!!driver,
  async verify(config){const t=transport(config);try{await t.verify();}catch(e){throw new ReportsError(e.code==='EAUTH'?'smtp_auth_failed':'smtp_connection_failed',422);}finally{t.close();}},
  async send(config,{recipients,name,id,scheduledAt,window,attachment}){
   const t=transport(config);try{
    const result=await t.sendMail({from:config.from,to:'Destinataires métier:;',envelope:{from:config.from,to:recipients},
     messageId:`<zenata-${id}@${config.from.split('@')[1]}>`,subject:'Zenata · '+name,
     text:`Rapport Gestion des flux — Zenata Port Sec\n\nPériode UTC : ${window.from} inclus à ${window.to} exclu.\nLes heures locales et les détails par client figurent dans le classeur Excel joint.\n\nEntrées/sorties : mouvements de conteneurs. Stock : présence au parc en fin de période.`,
     attachments:[{filename:`Zenata-${scheduledAt.slice(0,10)}.xlsx`,content:attachment,contentType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}],
     disableFileAccess:true,disableUrlAccess:true,
    });
    return {accepted:(result.accepted??[]).length,rejected:(result.rejected??[]).length};
   }catch(e){const error=new ReportsError(e.code==='EAUTH'?'smtp_auth_failed':'smtp_send_failed',503);
    error.deliveryUncertain=!['EAUTH','EENVELOPE','ECONNECTION','ETLS'].includes(e.code);throw error;
   }finally{t.close();}
  },
 };
}
module.exports={createMailer};
