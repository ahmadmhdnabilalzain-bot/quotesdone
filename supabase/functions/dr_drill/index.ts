// dr_drill — disaster-recovery restore drill.
// Downloads backup JSON files, parses them, reloads into public.dr_restore,
// and reports backup-vs-live row counts + schema-key integrity. Secret-gated.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(SUPABASE_URL, SERVICE_KEY);
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'dr_drill', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Content-Type':'application/json'};
const j=(o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:cors});

// small, business-critical tables + a required key to prove schema integrity
const TABLES:[string,string][]=[
  ['pricing_config','id'],['customers','id'],['quotes','id'],
  ['inquiries','id'],['transactions','id'],['inquiry_matches','inquiry_id']];

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  const sb=createClient(SUPABASE_URL,SERVICE_KEY);
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  const { data:secrets, error:secretsErr } = await sb.from('app_secrets').select('key,value').eq('key','inbound_secret');
  const secret=(secrets||[])[0]?.value;
  if(!secret || body.__secret!==secret){
    await logRun('error', { unauthorized:1, secret_configured: secret?1:0 }, secret ? 'Disaster-recovery drill rejected a caller with a wrong __secret; no restore drill ran. If this was the scheduled cron its secret is stale, which means backups are going unverified and a real outage could find them unrestorable.' : ('Disaster-recovery drill could not read inbound_secret from app_secrets, so every call including the scheduled cron is rejected with 401. The backup restore drill never runs and nobody is verifying that backups are restorable. ' + String(secretsErr?.message || 'no inbound_secret row')));
    return j({error:'unauthorized'},401);
  }

  // resolve day: explicit or latest folder that has a _manifest.json
  let day=body.day as string|undefined;
  let listErrMsg='';
  if(!day){
    const { data:root, error:listErr } = await sb.storage.from('backups').list('',{limit:1000});
    if(listErr) listErrMsg='Could not list the backups storage bucket, so the drill could not even find a backup to restore: '+String(listErr.message||listErr)+'. ';
    const days=(root||[]).map((e:any)=>e.name).filter((n:string)=>/^\d{4}-\d{2}-\d{2}$/.test(n)).sort();
    day=days[days.length-1];
  }
  if(!day){
    await logRun('error', { day:null }, listErrMsg+'No dated backup folder was found in the backups bucket, so the disaster-recovery drill did not run. Either backups are not being written at all or they are not where the drill looks; an outage right now may be unrecoverable.');
    return j({error:'no_backup_folder'},404);
  }

  const failNotes:string[]=[];
  const { error:wipeErr } = await sb.from('dr_restore').delete().neq('id',0); // clean slate
  if(wipeErr) failNotes.push('Could not clear the dr_restore staging table before the drill, so restored-row counts are compared against leftover rows from a previous run and the drill result cannot be trusted: '+String(wipeErr.message||wipeErr)+'. ');
  const report:any[]=[]; let ok=true;
  for(const [tbl,key] of TABLES){
    const row:any={ table:tbl };
    try{
      const { data:blob, error:de } = await sb.storage.from('backups').download(`${day}/${tbl}.json`);
      if(de||!blob){ row.status='backup_missing'; row.error=de?.message; ok=false; report.push(row); failNotes.push('Backup file '+day+'/'+tbl+'.json is missing, so the '+tbl+' table has no verified backup and could not be restored in a real outage. '); continue; }
      const arr=JSON.parse(await blob.text());
      row.backup_rows=Array.isArray(arr)?arr.length:0;
      // restore into staging
      if(row.backup_rows>0){
        const chunk=arr.map((r:any)=>({kind:tbl,row:r}));
        let insertErrMsg='';
        for(let i=0;i<chunk.length;i+=500){ const { error:ie } = await sb.from('dr_restore').insert(chunk.slice(i,i+500)); if(ie&&!insertErrMsg) insertErrMsg=String(ie.message||ie); }
        if(insertErrMsg) failNotes.push('Restoring '+tbl+' into the dr_restore staging table failed part-way, so the backup for '+tbl+' is not proven restorable: '+insertErrMsg+'. ');
      }
      const { count:restored, error:rcErr } = await sb.from('dr_restore').select('*',{count:'exact',head:true}).eq('kind',tbl);
      if(rcErr) failNotes.push('Could not count restored rows for '+tbl+', so its restore could not be verified: '+String(rcErr.message||rcErr)+'. ');
      row.restored_rows=restored||0;
      row.key_ok = row.backup_rows===0 ? true : (arr[0] && Object.prototype.hasOwnProperty.call(arr[0],key));
      const { count:live, error:lcErr } = await sb.from(tbl).select('*',{count:'exact',head:true});
      if(lcErr) failNotes.push('Could not count live rows in '+tbl+', so backup-vs-live drift for that table was not checked: '+String(lcErr.message||lcErr)+'. ');
      row.live_rows=live||0;
      row.restore_ok = row.restored_rows===row.backup_rows && row.key_ok;
      row.status = row.restore_ok ? 'ok' : 'mismatch';
      if(!row.restore_ok) ok=false;
    }catch(e){ row.status='error'; row.error=String(e).slice(0,160); ok=false; failNotes.push('Drill threw while restoring '+tbl+', so that table is not proven restorable: '+String(e).slice(0,160)+'. '); }
    report.push(row);
  }
  const total_restored=report.reduce((a,r)=>a+(r.restored_rows||0),0);
  const counts={ day, total_restored, tables_checked:report.length, tables_failed:report.filter((r:any)=>r.status!=='ok').length, failed_tables:report.filter((r:any)=>r.status!=='ok').map((r:any)=>r.table) };
  if(ok && !failNotes.length) await logRun('ok', counts, '');
  else await logRun('error', counts, (failNotes.join('') || 'Disaster-recovery drill finished with mismatches, so one or more backups are not proven restorable. ')+'Backups for the failing tables cannot be relied on for recovery.');
  return j({ ok, day, tables:report, total_restored, note:'Restored into public.dr_restore (staging); live tables untouched.' });
});
