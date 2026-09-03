import { requireInternal } from '../_shared/internal_auth.ts';
// dr_drill — disaster-recovery restore drill.
// Downloads backup JSON files, parses them, reloads into public.dr_restore,
// and reports backup-vs-live row counts + schema-key integrity. Secret-gated.
//
// PAGE-LEVEL RESUMPTION (13 Aug 2026). PR #286 changed `backup` to write
// `${stamp}/${table}/page_NNNN.json` because whole-table dumps no longer fit in one worker. This
// drill still downloaded `${day}/${table}.json`, so every table read `backup_missing` and the only
// assertion that this company's backups are restorable had been failing wholesale.
//
// Three shapes were measured and all three died with HTTP 546 WORKER_RESOURCE_LIMIT:
//   concatenate a table's pages into one array   -> 546 at  62s
//   stream each page straight into dr_restore    -> 546 at  93s
//   chain at TABLE level (one table per hop)     -> 546 at 110s
// The third fails because a single table already exceeds the budget: kb_chunks is 96 pages, about
// 192 inserts of 500 rows. So the resume point cannot be a table — it has to be a PAGE. This chain
// carries {table index, page index, rows restored so far} and is free to stop between two pages of
// the same table, exactly as `backup` stops between two pages when it writes them.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(SUPABASE_URL, SERVICE_KEY);
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return (data?.value as string|undefined) || undefined; }
async function logRun(status: string, counts: Record<string, unknown>, note: string, started: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'dr_drill', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: started, finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging break the function */ }
}
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'*','Content-Type':'application/json'};
const j=(o:unknown,s=200)=>new Response(JSON.stringify(o),{status:s,headers:cors});

// small, business-critical tables + a required key to prove schema integrity
// THE SIX ORIGINALS ARE THE REVENUE PATH, AND FIVE OF THEM ARE EMPTY IN PRODUCTION. Drilling only
// those made the report structurally incapable of finding anything: `total_restored: 1`. The
// tables that actually carry this company's value today are the knowledge estate — leads is
// 11.4 MB of backup, agent_knowledge 3.0 MB — and none of them was ever drilled. Keep the revenue
// path (it will matter the day the first customer signs up) and add what exists now.
const TABLES:[string,string][]=[
  ['pricing_config','id'],['customers','id'],['quotes','id'],
  ['inquiries','id'],['transactions','id'],['inquiry_matches','inquiry_id'],
  ['leads','id'],['agent_knowledge','id'],['kb_chunks','id'],
  ['dept_library','id'],['ops_knowledge','record_id']];

const SLICE_MS = 25000;   // hand off well inside the worker's budget; the inserts are the slow part
const MAX_HOPS = 60;      // kb_chunks alone is ~96 pages; a runaway chain must stop and be visible

// One table's progress as it travels between hops. `page` is the next page to read, `rows` and
// `restored` are what previous hops already put into dr_restore for this table.
type Slot = { t:string; key:string; page:number; rows:number; restored:number; key_ok:boolean|null; npages:number };

Deno.serve(async (req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  const sb=createClient(SUPABASE_URL,SERVICE_KEY);
  let body:any={}; try{ body=await req.json(); }catch(_e){}
  // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
  // per-context credential and the legacy shared secret, and records which one called.
  const __auth = await requireInternal(admin, body?.__secret, 'dr_drill');
  const started = typeof body?.__started === 'string' ? body.__started : new Date().toISOString();
  if(!__auth.ok){
    await logRun('error', { unauthorized:1, verifier_status: __auth.status }, __auth.status !== 503 ? 'Disaster-recovery drill rejected a caller with a wrong __secret; no restore drill ran. If this was the scheduled cron its secret is stale, which means backups are going unverified and a real outage could find them unrestorable.' : ('Disaster-recovery drill could not reach the credential verifier, so every call including the scheduled cron is rejected. The backup restore drill never runs and nobody is verifying that backups are restorable. ' + String(__auth.message || 'verifier unavailable')), started);
    return j({error:'unauthorized'},401);
  }

  const hop = Number(body?.__hop || 0);
  // ONE CHAIN, ONE RUN ID. restored_rows was counted as "every dr_restore row with this kind", so a
  // second chain running beside the first counted its rows as well and reported the backup as
  // unrestorable — measured 13 Aug 2026 at exactly 2x on kb_chunks, dept_library and ops_knowledge
  // when a manual run overlapped one already hopping. A false alarm on the only assertion that this
  // company's backups are restorable is how a real alarm gets muted. The id is minted on hop 0 and
  // travels with the chain.
  const runId = (typeof body?.__run === 'string' && body.__run) ? body.__run : crypto.randomUUID();
  const t0 = Date.now();
  const deadline = t0 + SLICE_MS;
  const failNotes:string[] = Array.isArray(body?.__notes) ? body.__notes.map(String) : [];
  const report:any[] = Array.isArray(body?.__report) ? body.__report : [];
  let manifestPages:Record<string,number> = (body?.__mpages && typeof body.__mpages==='object') ? body.__mpages : {};
  let day = body.day as string|undefined || body.__day as string|undefined;

  if(hop >= MAX_HOPS){
    await logRun('error', { day, hop, done:report.length }, 'Disaster-recovery drill chain exceeded '+MAX_HOPS+' hops and was stopped rather than left looping. The backup is NOT proven restorable: '+report.length+' of '+TABLES.length+' tables finished.', started);
    return j({error:'max_hops', day, done:report.length},200);
  }

  let queue:Slot[];
  if(Array.isArray(body?.__queue)){
    queue = body.__queue.map((q:any)=>({ t:String(q.t), key:String(q.key), page:Number(q.page||0), rows:Number(q.rows||0), restored:Number(q.restored||0), key_ok: (q.key_ok===null||q.key_ok===undefined) ? null : !!q.key_ok, npages:Number(q.npages||-1) }));
  } else {
    // ---- hop 0 only: resolve the day, read the manifest, and clear the staging table ----------
    let listErrMsg='';
    if(!day){
      const { data:root, error:listErr } = await sb.storage.from('backups').list('',{limit:1000});
      if(listErr) listErrMsg='Could not list the backups storage bucket, so the drill could not even find a backup to restore: '+String(listErr.message||listErr)+'. ';
      const days=(root||[]).map((e:any)=>e.name).filter((n:string)=>/^\d{4}-\d{2}-\d{2}$/.test(n)).sort();
      day=days[days.length-1];
    }
    if(!day){
      await logRun('error', { day:null }, listErrMsg+'No dated backup folder was found in the backups bucket, so the disaster-recovery drill did not run. Either backups are not being written at all or they are not where the drill looks; an outage right now may be unrecoverable.', started);
      return j({error:'no_backup_folder'},404);
    }
    // The manifest's per-table page count is what makes a PARTIAL restore detectable: a missing
    // page otherwise reads as a smaller table, which is a backup that looks fine.
    try{
      const { data:mb } = await sb.storage.from('backups').download(`${day}/_manifest.json`);
      if(mb){ const m = JSON.parse(await mb.text()); if(m?.pages && typeof m.pages==='object') manifestPages = m.pages; }
    }catch(_e){ /* absent manifest is handled per-table below */ }
    // WIPE ON HOP 0 ONLY. Every later hop is adding rows to this same staging table; clearing it
    // again mid-chain would delete what earlier hops restored and make restored_rows meaningless.
    // ONE CHAIN AT A TIME. A hop that takes ~28s is long enough for the edge gateway to retry the
    // POST, and a retry starts a SECOND chain: measured 13 Aug 2026, two hop-0s thirty seconds
    // apart from a single request, both hopping through the same staging table. run_id keeps each
    // chain's counts honest, but two chains still double the work and the storage reads, so a
    // chain that finds another actively writing stands down instead.
    const { count:busy } = await sb.from('dr_restore').select('*',{count:'exact',head:true}).gte('drill_at', new Date(Date.now()-180e3).toISOString());
    if((busy||0) > 0){
      await logRun('ok', { day, skipped:'chain_already_running' }, 'A disaster-recovery drill was already writing to dr_restore, so this second chain stood down rather than doubling the work. The running chain reports on its own.', started);
      return j({ ok:true, skipped:'chain_already_running' });
    }
    // Clears anything older than three minutes rather than the whole table, so nothing another
    // chain is mid-way through is ever deleted underneath it.
    // BATCHED, BECAUSE ONE STATEMENT COULD NOT FINISH (13 Aug 2026).
    //
    // This was a single conditional DELETE. On 12 Aug at 20:31 it returned "canceling statement due
    // to statement timeout" against a dr_restore holding a quarter of a million rows, and the drill
    // then counted three runs stacked on top of each other:
    //
    //   kb_chunks      95,983 expected   287,949 restored   exactly 3x
    //   dept_library    1,456 expected     4,368 restored   exactly 3x
    //   ops_knowledge   3,735 expected    11,205 restored   exactly 3x
    //
    // It reported 7 of 11 tables "not proven restorable". The backups were fine — the two runs at
    // 20:35 and 20:40, once the table was small enough to clear, both came back 11/11 with 0 failed.
    // What actually failed was the drill's own housekeeping, and the failure mode is the dangerous
    // one: not "the backup is bad" but "the verdict on the backup cannot be trusted".
    //
    // TRUNCATE is NOT the fix. The predicate is load-bearing — see the comment above: anything
    // another chain is mid-way through must survive, and the 180-second guard is a check-then-act
    // that a table-wide wipe would race. Bounded passes keep the predicate and keep every statement
    // small enough to finish. The loop stops early the moment a pass comes back empty, which is
    // the normal case.
    //
    // THIS CLEAR IS FOR LEFTOVERS, NOT FOR THE PREVIOUS DRILL (3 Sep 2026). A completed drill now
    // deletes its own rows at the end (see the run_id cleanup after logRun), so what this loop
    // meets is normally nothing. Its capacity is what PostgREST's max-rows allows — a select is
    // capped at 1,000 rows whatever .limit says, measured: "cleared 200000 row(s) in 200 passes"
    // — so 40 passes clears 40,000 rows, which is only the residue of a CRASHED chain. A residue
    // larger than that is reported below as 'still remain' rather than carried into the counts,
    // and drains over the following drills. ponytail: 40 x 1,000 per pre-clear; move the clear
    // server-side (one bounded DELETE by ctid per pass) if a crashed chain must heal in one run.
    let wiped = 0, wipePasses = 0; let wipeErr: { message?: string } | null = null;
    const cutoff = new Date(Date.now()-180e3).toISOString();
    for (; wipePasses < 40; wipePasses++) {
      const { data: stale, error: selErr } = await sb.from('dr_restore').select('id').lt('drill_at', cutoff).limit(5000);
      if (selErr) { wipeErr = selErr; break; }
      if (!stale || !stale.length) break;
      const { error: delErr } = await sb.from('dr_restore').delete().in('id', stale.map((r: { id: number }) => r.id));
      if (delErr) { wipeErr = delErr; break; }
      wiped += stale.length;
    }
    // Still not empty after the pass budget is the same untrustworthy state as a timeout, and is
    // reported as such rather than being carried silently into the row counts.
    if (!wipeErr && wipePasses >= 40) {
      const { count: left } = await sb.from('dr_restore').select('*', { count:'exact', head:true }).lt('drill_at', cutoff);
      if (left) wipeErr = { message: 'cleared '+wiped+' row(s) in 40 passes and '+left+' still remain' };
    }
    if(wipeErr) failNotes.push('Could not clear the dr_restore staging table before the drill, so restored-row counts are compared against leftover rows from a previous run and the drill result cannot be trusted: '+String(wipeErr.message||wipeErr)+'. ');
    queue = TABLES.map(([t,key])=>({ t, key, page:0, rows:0, restored:0, key_ok:null, npages:-1 }));
  }

  // ---- work until the slice is spent, stopping between two pages of the same table -------------
  while(queue.length && Date.now() < deadline){
    const slot = queue[0];
    const row:any = { table:slot.t };
    try{
      // How many pages does this day hold for this table? Listed once per table and carried on the
      // slot, so a resumed table does not re-list.
      if(slot.npages < 0){
        const { data:objs } = await sb.storage.from('backups').list(`${day}/${slot.t}`,{limit:1000});
        slot.npages = (objs||[]).filter((o:any)=>/^page_\d+\.json$/.test(o.name)).length;
      }

      if(slot.npages === 0){
        // OLD SINGLE-FILE LAYOUT. Days written before the paged backup shipped are still valid
        // backups and must still be drillable, so the pre-#286 path stays.
        const { data:blob, error:de } = await sb.storage.from('backups').download(`${day}/${slot.t}.json`);
        if(de||!blob){ row.status='backup_missing'; row.error=de?.message; failNotes.push('Backup for '+slot.t+' is missing on '+day+' (no paged folder and no single file), so that table has no verified backup and could not be restored in a real outage. '); report.push(row); queue.shift(); continue; }
        const arr=JSON.parse(await blob.text());
        slot.rows = Array.isArray(arr)?arr.length:0;
        slot.key_ok = slot.rows===0 ? true : !!(arr[0] && Object.prototype.hasOwnProperty.call(arr[0],slot.key));
        for(let i=0;i<slot.rows;i+=500){ const { error:ie } = await sb.from('dr_restore').insert(arr.slice(i,i+500).map((r:any)=>({kind:slot.t,row:r,run_id:runId}))); if(ie) failNotes.push('Restoring '+slot.t+' into the dr_restore staging table failed part-way, so the backup for '+slot.t+' is not proven restorable: '+String(ie.message||ie)+'. '); }
        slot.page = 1; slot.npages = 1;
      } else {
        // PAGED LAYOUT. One page per iteration; the deadline is checked between pages, which is the
        // whole point — a 96-page table can span as many hops as it needs.
        while(slot.page < slot.npages && Date.now() < deadline){
          const name=`${day}/${slot.t}/page_${String(slot.page).padStart(4,'0')}.json`;
          const { data:blob, error:de } = await sb.storage.from('backups').download(name);
          if(de||!blob){ failNotes.push('Backup page '+name+' is missing, so '+slot.t+' cannot be fully restored. '); row.error='missing '+name; slot.page++; continue; }
          const arr=JSON.parse(await blob.text());
          const n=Array.isArray(arr)?arr.length:0;
          if(slot.key_ok===null) slot.key_ok = n===0 ? true : !!(arr[0] && Object.prototype.hasOwnProperty.call(arr[0],slot.key));
          for(let i=0;i<n;i+=500){ const { error:ie } = await sb.from('dr_restore').insert(arr.slice(i,i+500).map((r:any)=>({kind:slot.t,row:r,run_id:runId}))); if(ie) failNotes.push('Restoring '+slot.t+' into the dr_restore staging table failed part-way, so the backup for '+slot.t+' is not proven restorable: '+String(ie.message||ie)+'. '); }
          slot.rows += n; slot.page++;
        }
        if(slot.page < slot.npages) break;   // out of budget mid-table: the slot keeps its page index
      }

      // ---- the table is finished: the assertions, unchanged ------------------------------------
      row.backup_rows = slot.rows;
      row.pages = slot.npages;
      const { count:restored, error:rcErr } = await sb.from('dr_restore').select('*',{count:'exact',head:true}).eq('kind',slot.t).eq('run_id',runId);
      if(rcErr) failNotes.push('Could not count restored rows for '+slot.t+', so its restore could not be verified: '+String(rcErr.message||rcErr)+'. ');
      row.restored_rows = restored||0;
      row.key_ok = slot.key_ok === null ? true : slot.key_ok;
      // THE LIVE COUNT IS DRIFT INFORMATION, NOT THE RESTORE VERDICT (3 Sep 2026). An exact count
      // of kb_chunks — 2.69M rows — hit the statement timeout, the error object stringified as
      // "[object Object]", and a drill that had restored all 11 tables with 0 failures logged
      // 'error' and "Backups for the failing tables cannot be relied on for recovery" over a
      // number it never needed. The planner's estimate is what the drift figure is for; a count
      // that still fails is recorded on the row as unknown and asserts nothing.
      const { count:live, error:lcErr } = await sb.from(slot.t).select('*',{count:'estimated',head:true});
      if(lcErr){ row.live_rows = null; row.live_count_error = String(lcErr.message || lcErr.code || JSON.stringify(lcErr)).slice(0,160); }
      else row.live_rows = live||0;
      // PAGE COUNT AGAINST THE MANIFEST. `backup` records how many pages it wrote per table; if the
      // bucket holds fewer, rows were lost between writing and reading and the smaller row count
      // would otherwise look like a smaller table.
      const expected = Number(manifestPages[slot.t]);
      row.pages_expected = Number.isFinite(expected) ? expected : null;
      const pagesOk = !Number.isFinite(expected) || expected < 0 || expected === slot.npages;
      if(!pagesOk) failNotes.push('The backup manifest says '+slot.t+' was written as '+expected+' page(s) but only '+slot.npages+' are present, so part of that backup is missing and the row count below understates the loss. ');
      // AN EMPTY BACKUP USED TO PASS. `backup_rows===0` forced key_ok true and made
      // restored_rows===backup_rows trivially true, so a table whose backup file is the two-byte
      // string `[]` scored `ok`. Measured on production 6 Aug 2026: 215 of the 1,075 objects in the
      // `backups` bucket are <=2 bytes, and the 1 Aug drill still reported
      // {tables_checked:6, tables_failed:0, total_restored:1} — the only assertion that this
      // company's backups are restorable, and it was green because five of its six tables are
      // empty in production and the sixth holds one row.
      //
      // The distinction that matters is live_rows: an empty backup of an empty table is correct,
      // an empty backup of a populated table is a lost backup. Asserting `backup_rows>0` outright
      // would fail every genuinely-empty table and get muted within a week.
      const emptyBackupOfLiveTable = row.live_rows>0 && row.backup_rows===0;
      if(emptyBackupOfLiveTable) failNotes.push('The backup file for '+slot.t+' is empty while the live table holds '+row.live_rows+' row(s), so that table has no restorable backup at all. ');
      // A COUNT MISMATCH USED TO FAIL SILENTLY. restore_ok went false and the run said only
      // "finished with mismatches" — the one condition the drill exists to detect was the one it
      // did not describe. Measured 13 Aug 2026: the first full-chain run reported four failed
      // tables and no reason for any of them.
      if(row.restored_rows!==row.backup_rows) failNotes.push('Restoring '+slot.t+' put '+row.restored_rows+' row(s) into dr_restore from a backup holding '+row.backup_rows+' (live '+row.live_rows+'), so the backup and the restore disagree and that table is not proven restorable. ');
      if(!row.key_ok) failNotes.push('The first restored row of '+slot.t+' has no "'+slot.key+'" column, so the backup does not carry that table\'s schema key and a restore would not reconstruct it. ');
      row.restore_ok = row.restored_rows===row.backup_rows && row.key_ok && !emptyBackupOfLiveTable && pagesOk;
      row.status = row.restore_ok ? 'ok' : (emptyBackupOfLiveTable ? 'empty_backup' : (!pagesOk ? 'pages_missing' : 'mismatch'));
    }catch(e){ row.status='error'; row.error=String(e).slice(0,160); failNotes.push('Drill threw while restoring '+slot.t+', so that table is not proven restorable: '+String(e).slice(0,160)+'. '); }
    report.push(row);
    queue.shift();
  }

  if(queue.length){
    // Hand the rest to a fresh worker with the exact page to resume at. Fire-and-forget: this
    // invocation has no budget left to wait. A crash mid-chain leaves no agent_runs row, which is
    // what fn_backup_watch already alerts on.
    const s = await sec('cred_cron_backup');
    // THE HAND-OFF WAS DROPPED ONCE IN TEN (3 Sep 2026). A bare fire-and-forget fetch is not owed
    // any lifetime past the Response: the worker can be torn down before the outgoing POST is
    // flushed. Measured: hop 9 returned 200 at 20:32:16, no hop 10 ever arrived, 228,002 rows sat
    // restored and the chain ended with no agent_runs row — a silent non-verdict on the only
    // assertion that backups restore. EdgeRuntime.waitUntil keeps the worker alive until the
    // hand-off has been sent; the fallback is the old shape where the runtime lacks it.
    const handoff = fetch(SUPABASE_URL + '/functions/v1/dr_drill', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body: JSON.stringify({ __secret:s, __day:day, __run:runId, __queue:queue, __report:report, __notes:failNotes,
                             __mpages:manifestPages, __started:started, __hop:hop+1 }),
    }).then((r)=>{ if(!r.ok) console.error('dr_drill hand-off to hop '+(hop+1)+' returned HTTP '+r.status); }).catch((e)=>console.error('dr_drill hand-off to hop '+(hop+1)+' failed: '+String(e).slice(0,160)));
    const rt = (globalThis as any).EdgeRuntime;
    if(rt && typeof rt.waitUntil === 'function') rt.waitUntil(handoff);
    return j({ ok:true, day, hop, done:report.length, remaining:queue.length, resume:{ table:queue[0].t, page:queue[0].page } });
  }

  const ok = report.every((r:any)=>r.status==='ok') && !failNotes.length;
  const total_restored=report.reduce((a,r)=>a+(r.restored_rows||0),0);
  // The per-table numbers travel in the RESPONSE, and the chain's last hop answers a
  // fire-and-forget POST that nobody reads — so the only durable record was "4 tables failed".
  // They go in the row.
  const counts={ day, total_restored, hops:hop+1, tables_checked:report.length, tables_failed:report.filter((r:any)=>r.status!=='ok').length, failed_tables:report.filter((r:any)=>r.status!=='ok').map((r:any)=>r.table),
    tables: report.map((r:any)=>({ t:r.table, backup:r.backup_rows??null, restored:r.restored_rows??null, live:r.live_rows??null, pages:r.pages??null, expected:r.pages_expected??null, s:r.status })) };
  if(ok) await logRun('ok', counts, '', started);
  else await logRun('error', counts, (failNotes.join('') || 'Disaster-recovery drill finished with mismatches, so one or more backups are not proven restorable. ')+'Backups for the failing tables cannot be relied on for recovery.', started);
  // THE DRILL CLEANS UP AFTER ITSELF (3 Sep 2026). The pre-clear above is bounded at 40 passes and
  // PostgREST caps each at 1,000 rows, while one drill now leaves ~234,000 rows in dr_restore
  // (201 pages of kb_chunks alone) — so every drill was going to find the last drill's rows, run
  // out of passes and call its own verdict untrustworthy. The verdict is written first; this
  // runs after the response, kept alive by the runtime, deletes only THIS run's rows by run_id,
  // and is bounded too: 400 x 1,000. An exhausted budget is logged; the next pre-clear reports
  // what it finds rather than counting it.
  const cleanup = (async () => {
    let n = 0, passes = 0;
    for (; passes < 400; passes++) {
      const { data: mine, error: se } = await sb.from('dr_restore').select('id').eq('run_id', runId).limit(1000);
      if (se || !mine || !mine.length) break;
      const { error: de } = await sb.from('dr_restore').delete().in('id', mine.map((r: { id: number }) => r.id));
      if (de) break;
      n += mine.length;
    }
    if (passes >= 400) console.error('dr_drill cleanup of run '+runId+' exhausted 400 passes after '+n+' row(s); the next drill reports the leftovers');
  })().catch((e)=>console.error('dr_drill cleanup of run '+runId+' failed: '+String(e).slice(0,160)));
  const rtc = (globalThis as any).EdgeRuntime;
  if(rtc && typeof rtc.waitUntil === 'function') rtc.waitUntil(cleanup); else await cleanup;
  return j({ ok, day, tables:report, total_restored, hops:hop+1, note:'Restored into public.dr_restore (staging); live tables untouched.' });
});
