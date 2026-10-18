// EVERY CONVERSATION IS KEPT, BACKED UP, AND THE SALES ENGINEER CAN READ IT.
//
// The founder, 14 Sep 2026: "keep in mind that all conversations need to be saved and the sales
// agent has access to them at any time. just in case we needed them for any reason" - and every
// email printed to PDF and kept in "supabase and dropbox".
//
// Measured when this was written: no routine, cron job or edge function deleted from any
// conversation store; the gaps were truncation (inbound email at 8,000 characters and receipts
// replaced by a summary, WhatsApp at 2,000), a portal chat that was never saved, and a sales
// engineer with no way to read any of it. Those are fixed in
// scripts/sql/every_conversation_is_kept_backed_up_twice_and_readable_by_the_sales_engineer.sql.
// This check fails if any of it comes undone:
//   1. a conversation store gains a purge (a routine, a cron command or an edge function)
//   2. the sales engineer loses read access (routine, grant, the seat's action)
//   3. a message older than the grace has no PDF in the backups bucket, or its PDF has no Dropbox
//      queue row - the symptom; and resilience_ping still calls the archiver - the mechanism,
//      because a quiet estate passes the symptom with nothing to archive.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

// sms_messages joined on 22 Sep 2026 with the sms_inbound function: until then the number's SmsUrl
// was Twilio's demo responder and no inbound SMS was recorded anywhere. It is a conversation store
// by the founder's rule, so the no-purge property is enforced here rather than promised in a comment.
const STORES = ['inbound_messages', 'notifications', 'wa_messages', 'wa_turn', 'wa_conversation', 'messages',
  'sms_messages',
  'rfq_clarification', 'assistant_logs', 'contact_messages', 'complaint_tickets', 'quote_review_messages',
  'chat_threads', 'agent_chats', 'conversation_archive'];
const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const FN = join(ROOT, 'supabase', 'functions');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

function tsFiles(dir, out = []) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) { if (e !== 'node_modules' && e !== 'vendor') tsFiles(p, out); }
    else if (e.endsWith('.ts') && !e.endsWith('.test.ts')) out.push(p);
  }
  return out;
}

test('no edge function removes a row from a conversation store', () => {
  const re = new RegExp(`from\\(\\s*['"](${STORES.join('|')})['"]\\s*\\)[\\s\\S]{0,200}?\\.(delete)\\(`, 'g');
  const hits = [];
  for (const f of tsFiles(FN)) {
    for (const stmt of readFileSync(f, 'utf8').split(';')) { if (re.test(stmt)) hits.push(f.slice(ROOT.length)); re.lastIndex = 0; }
  }
  assert.deepEqual(hits, [], 'a conversation store gained a purge in: ' + hits.join(', '));
});

test('the sales engineer seat reads the whole record, and the heartbeat archives it', () => {
  const se = readFileSync(join(FN, 'sales_engineer', 'index.ts'), 'utf8');
  assert.match(se, /action === 'conversations'/, 'sales_engineer lost its conversations action');
  assert.match(se, /rpc\('fn_conversation_record'/, 'the conversations action no longer reads fn_conversation_record');
  assert.match(se, /from\('assistant_logs'\)\.insert/, 'the portal chat with the sales engineer is no longer saved');
  const rp = readFileSync(join(FN, 'resilience_ping', 'index.ts'), 'utf8');
  // 15 Sep 2026 (PR #714): ticks run from the STEPS list via runSteps, so "called before the healthy early
  // return" is: archiveTick is a STEPS entry, and runSteps(STEPS runs before the healthy return.
  //
  // 18 Sep 2026 (PR #754): the order moved into Postgres and the list became the STEP_RUN map. Three
  // things are asserted now instead of two, because the founder's rule is the PDF within one BEAT and
  // the new design gives two ways to lose that which the old list did not have:
  //   * the schedule must name `archive`, or it is never planned at all;
  //   * it must be `always`, or the 110 s backstop skips it — which is exactly what was happening
  //     (duty:heartbeat:archive, "not run: the tick passed its 110s deadline", seen 27 times on 18 Sep).
  const steps = rp.slice(rp.indexOf('const STEP_RUN'), rp.indexOf('const DECLARED_ORDER'));
  assert.ok(steps.length > 0, 'the STEP_RUN map was not found before DECLARED_ORDER');
  assert.match(steps, /archive: \{ run: archiveTick, always: true \}/,
    'archiveTick is not a heartbeat step that runs even past the deadline');
  const seed = readFileSync(join(ROOT, 'scripts', 'sql',
    'the_tick_runs_what_is_stalest_not_what_is_first_in_the_list.sql'), 'utf8');
  assert.match(seed, /\('archive',\s+interval '15 min',\s+\d+,\s+'last'/,
    'the schedule does not name archive as a drain that runs every tick');
  const call = rp.indexOf('await runSteps(steps'), early = rp.indexOf('if (healthy) return J(');
  assert.ok(call > 0 && early > 0 && call < early, 'resilience_ping must call the archiver before the healthy early return');
  assert.match(rp, /\/conversation_archive'/, 'archiveTick no longer calls conversation_archive');
  // 6 Oct 2026: one sweep of 4 a beat (16 an hour) left 27 messages past the 2-hour line after a
  // 106-mail invitation run. The beat runs several sweeps in parallel over disjoint offsets.
  const n = Number(rp.match(/ARCHIVE_SWEEPS = (\d+)/)?.[1] ?? 0);
  assert.ok(n >= 4, 'archiveTick must run at least 4 parallel sweeps a beat (64 PDFs an hour)');
  assert.match(rp, /Promise\.all\(Array\.from\(\{ length: ARCHIVE_SWEEPS \}/, 'the archive sweeps are not run in parallel');
  const ca = readFileSync(join(ROOT, 'supabase', 'functions', 'conversation_archive', 'index.ts'), 'utf8');
  assert.match(ca, /p_limit: offset \+ limit/, 'conversation_archive does not take a disjoint offset slice');
  assert.match(ca, /\.slice\(offset\)/, 'conversation_archive does not take a disjoint offset slice');
});

test('no routine or cron job purges a conversation store', { skip: SKIP }, async () => {
  const del = 'de' + 'lete', trn = 'trun' + 'cate';
  const pat = `(${del}\\s+from|${trn}(\\s+table)?)\\s+(only\\s+)?(public\\.)?(${STORES.join('|')})\\b`;
  const fns = await sql(`select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                          where n.nspname = 'public' and p.prosrc ~* '${pat}'`);
  assert.deepEqual(fns.map((r) => r.sig), [], 'a routine purges a conversation store');
  const jobs = await sql(`select jobid, jobname from cron.job where command ~* '${pat}'`);
  assert.deepEqual(jobs, [], 'a cron job purges a conversation store');
});

test('the sales engineer can read every conversation, and nobody anonymous can', { skip: SKIP }, async () => {
  const [r] = await sql(`select to_regprocedure('public.fn_conversation_record(text,integer)') is not null as present,
      has_function_privilege('service_role', 'public.fn_conversation_record(text,integer)', 'execute') as svc,
      has_function_privilege('anon', 'public.fn_conversation_record(text,integer)', 'execute') as anon,
      has_function_privilege('authenticated', 'public.fn_conversation_record(text,integer)', 'execute') as auth,
      exists (select 1 from public.ceo_standing_grant where grant_key = 'sales.conversation_record'
               and grantee_role_id = 'sales_engineer' and active and (expires_at is null or expires_at > now())) as granted`);
  assert.equal(r.present, true, 'fn_conversation_record is gone');
  assert.equal(r.svc, true, 'the seats (service role) cannot execute fn_conversation_record');
  assert.equal(r.anon, false, 'anon can read every conversation');
  assert.equal(r.auth, false, 'any signed-in user can read every conversation');
  assert.equal(r.granted, true, 'the sales engineer has no active grant to read conversations');
});

test('every conversation older than two hours has its PDF and its Dropbox queue row', { skip: SKIP }, async () => {
  const [r] = await sql(`select public.fn_conversation_retention_breaches(interval '2 hours') as b`);
  assert.equal(Number(r.b.total), 0, 'not backed up: ' + JSON.stringify(r.b));
});
