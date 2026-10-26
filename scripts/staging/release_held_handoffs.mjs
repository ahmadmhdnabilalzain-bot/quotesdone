// release_held_handoffs.mjs — put the held handoffs back THROUGH the gate, not around it.
//
// WHY THIS EXISTS AND WHY IT IS NOT AN UPDATE. public.zzz_action_gate is a BEFORE INSERT trigger —
// pg_trigger.tgtype = 7 (ROW | BEFORE | INSERT). A bulk `update agent_actions set status='pending'`
// therefore does not re-run the gate, it OVERRIDES it: every row lands in whatever status the
// UPDATE names, including rows the gate would still refuse. That is the opposite of releasing them
// safely, and it is why the founder's brief says to ask first and to go row by row.
//
// The only way to get the gate's verdict on an existing row is to make it look like an insert. So
// each held handoff is re-inserted as a copy — the gate fires on the copy and decides its status —
// and the original is marked superseded only if the copy actually landed. One row per statement, so
// a failure part-way leaves a consistent ledger rather than half a bulk update.
//
// MEASURED 13 Aug 2026 by running exactly this in an aborted transaction on production:
//   35 held handoffs examined · 32 would RELEASE · 3 would stay HELD · 0 errored
//   still held: 2571 (reconcile open_escalations vs fn_ws_customers), 2787 (root-cause
//   resend_inbound), 2891 (confirm complaint template matches the published policy) — all low risk,
//   all genuinely needing a human, and the gate is right to keep them.
//
// DRY RUN BY DEFAULT. Without --commit it re-runs that same aborted-transaction probe and prints
// the verdict, changing nothing. --commit is the founder's decision to make, not this script's.
//
//   node scripts/staging/release_held_handoffs.mjs --ref=<project>            # dry run
//   node scripts/staging/release_held_handoffs.mjs --ref=<project> --commit   # release
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { readFileSync, existsSync } from 'node:fs';

const arg = (n) => (process.argv.find((a) => a.startsWith(`--${n}=`)) || '').split('=').slice(1).join('=');
const REF = arg('ref');
const COMMIT = process.argv.includes('--commit');
if (!/^[a-z]{20}$/.test(REF)) { console.error('--ref=<project> is required and has no default'); process.exit(2); }

const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
if (!token) { console.error('no SUPABASE_ACCESS_TOKEN and no local access token'); process.exit(2); }

const q = async (sql) => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }), signal: AbortSignal.timeout(120000),
  });
  const body = await r.text();
  if (!r.ok) throw new Error(`${r.status}: ${body.slice(0, 400)}`);
  return JSON.parse(body);
};

console.log(`target ref = ${REF}   mode = ${COMMIT ? 'COMMIT' : 'dry run'}`);

const held = await q(`select id, agent, risk, coalesce(title,'') as title
                        from public.agent_actions
                       where kind = 'handoff' and status = 'needs_review'
                       order by id`);
console.log(`held handoffs: ${held.length}`);
if (!held.length) process.exit(0);

if (!COMMIT) {
  // The probe: same inserts, wrapped in a DO block that always raises so nothing survives.
  try {
    await q(`do $$
      declare r record; s text; rel int := 0; kept int := 0; err int := 0; d text := '';
      begin
        for r in select * from public.agent_actions where kind='handoff' and status='needs_review' order by id loop
          begin
            insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id, confidence)
            values (r.agent, r.kind, 'pending', r.risk, r.title, r.recommendation, r.detail, r.target_table, r.target_id, r.confidence)
            returning status into s;
            if s in ('pending','approved','auto_done','done') then rel := rel + 1;
            else kept := kept + 1; d := d || r.id || '=' || s || ' '; end if;
          exception when others then err := err + 1; d := d || r.id || '=ERR ';
          end;
        end loop;
        raise exception 'DRYRUN release=% hold=% err=% detail=%', rel, kept, err, left(d, 500);
      end $$;`);
    console.log('probe did not abort — that should be impossible; nothing was changed by design');
  } catch (e) {
    // Stop the detail at the first newline: the management API returns the RAISE text with
    // Postgres's own "CONTEXT: ..." trailer appended, and printing that reads as part of the answer.
    const m = String(e.message).match(/DRYRUN release=(\d+) hold=(\d+) err=(\d+) detail=([^\n\\]*)/);
    if (!m) throw e;
    console.log(`would RELEASE : ${m[1]}`);
    console.log(`would stay HELD: ${m[2]}${m[4].trim() ? '  (' + m[4].trim() + ')' : ''}`);
    console.log(`errored        : ${m[3]}`);
    console.log('\nnothing was changed. Re-run with --commit to release.');
  }
  process.exit(0);
}

// ---- commit: one row at a time, and only supersede an original whose copy actually landed -------
let released = 0, stillHeld = 0, failed = 0;
for (const h of held) {
  try {
    const [ins] = await q(`insert into public.agent_actions
        (agent, kind, status, risk, title, recommendation, detail, target_table, target_id, confidence)
      select agent, kind, 'pending', risk, title, recommendation, detail, target_table, target_id, confidence
        from public.agent_actions where id = ${h.id}
      returning id, status`);
    const landed = ['pending', 'approved', 'auto_done', 'done'].includes(ins.status);
    if (landed) {
      await q(`update public.agent_actions set status='superseded' where id = ${h.id} and status='needs_review'`);
      released++;
      console.log(`  released ${h.id} -> new ${ins.id} (${ins.status})  ${h.title.slice(0, 60)}`);
    } else {
      // The gate refused the copy, so the copy is the duplicate and it goes, not the original.
      await q(`delete from public.agent_actions where id = ${ins.id}`);
      stillHeld++;
      console.log(`  STILL HELD ${h.id} (gate said ${ins.status})  ${h.title.slice(0, 60)}`);
    }
  } catch (e) {
    failed++;
    console.log(`  FAILED ${h.id}: ${String(e.message).slice(0, 140)}`);
  }
}
console.log(`\nreleased ${released}, still held ${stillHeld}, failed ${failed}`);
