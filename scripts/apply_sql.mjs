// Apply a .sql file to the database, then VERIFY BY READING THE DEFINITION BACK OUT.
//
// THIS WAS A TWO-PROJECT PROMOTION UNTIL 15 AUG 2026. The founder's rule of 6 Aug was that a
// routine reaches production by reading a VERIFIED definition back out of staging and posting THAT
// verbatim — never by retyping a body. Staging (pglpqrhvozwepymcuunn) was deleted on 15 Aug at his
// instruction: "I don't want anything in staging that can affect our build up process by giving us
// old references which got upgraded". There is one project now.
//
// The rule survives the deletion; only its geometry changes. The verification was never "two
// projects agree" — it was "what is LIVE is what the file says, read back from the database rather
// than assumed from the fact that a POST returned 200". That read-back still happens, after the
// apply instead of between two projects, and it is still what makes the exit code mean something.
//
// What was LOST with staging, said plainly rather than papered over: there is no longer a rehearsal
// copy, so a file cannot be tried somewhere harmless first. That is why the default is now a DRY
// RUN. A bare invocation used to mean "staging only, nothing production sees"; if it had silently
// become "apply to production" every muscle-memory command in this repo's history would have become
// a live write.
//
//   node scripts/apply_sql.mjs scripts/sql/x.sql            # DRY RUN — guards only, no write
//   node scripts/apply_sql.mjs scripts/sql/x.sql --apply    # apply, then verify by read-back
//   node scripts/apply_sql.mjs scripts/sql/x.sql --promote  # accepted alias for --apply (history)
//   node scripts/apply_sql.mjs scripts/sql/x.sql --apply --ddl   # file also carries schema changes
//   node scripts/apply_sql.mjs scripts/sql/x.sql --apply --lock-timeout=3000   # lock_timeout other than 1500 ms (max 15000)
import { supabaseAccessToken } from './lib/supabase_token.mjs';
import { readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from './lib/qd_guard.mjs';

const file = process.argv[2];
// --promote is kept as an alias, not as a second mode. It is written into ~20 session briefs, the
// session skill and supabase/migrations_history/README.md; breaking it would turn every recorded
// command in this repo's own history into an error, and the two now mean the same thing.
const APPLY = process.argv.includes('--apply') || process.argv.includes('--promote');
// --ddl: the file also carries schema changes (columns, views, tables, indexes, cron rows) that
// pg_get_functiondef cannot express, so there is no routine definition to read back for them. What
// it buys now is the public-schema shape digest printed either side of the apply, so a file that
// was supposed to add a column and did not says so instead of exiting 0 on an empty routine list.
const DDL = process.argv.includes('--ddl');
if (!file) {
  console.error('usage: node scripts/apply_sql.mjs <file.sql> [--apply|--promote] [--ddl] [--lock-timeout=<ms, default 1500>]');
  process.exit(2);
}

// Unreviewed code never reaches production (scripts/lib/release_guard.mjs). Before any read or write.
if (APPLY) {
  const { releaseRefusal } = await import('./lib/release_guard.mjs');
  const why = releaseRefusal([file]);
  if (why) { console.error('REFUSED: ' + why + '. Merge it, or wait for its PR to go green.'); process.exit(2); }
}
const sql = readFileSync(file, 'utf8');
// Refused before anything is read from or written to the database (review of #661, scripts/lib/sql_text.mjs).
{
  const { refuseUnsignable } = await import('./lib/sql_text.mjs');
  const why = refuseUnsignable(sql, file);
  if (why) { console.error('REFUSED: ' + why); process.exit(2); }
}
const one = (rows) => (rows && rows[0]) ? Object.values(rows[0])[0] : null;

const token = supabaseAccessToken();

// RETRIES, BECAUSE THE FAILURE MODE HERE IS A HALF-APPLIED DATABASE. The management API
// rate-limits hard after a heavy session, so a 429 arriving between two routines in the same file
// would apply the first, throw on the second, and leave the database in a state no file describes.
// Observed on the first promotion attempt of session 15. Slow is expected; a 9-second gate taking
// 102 seconds is normal, not a hang.
// A 429 is refused before anything runs, so it is re-sent. A 5xx, or a connection that drops, is NOT re-sent here (13 Nov 2026,
// review of the replay guard, item 4): the session may have been cut after the file ran, or may still be running and holding
// its locks, and a second copy of a file that is not idempotent would apply twice. sendApply() below settles it first.
async function dbPost(q, attempt = 0) {
  let r;
  try {
    r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/database/query`, {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: q }),
    });
  } catch (e) { throw Object.assign(new Error(`database transport: ${e?.cause?.code || e?.message || e}`), { unsettled: true }); }
  const b = await r.text();
  if (r.status === 429 && attempt < 7) {
    const wait = Math.min(2000 * 2 ** attempt, 60000);
    console.log(`  ${r.status}; retrying in ${wait / 1000}s (attempt ${attempt + 1}/7)`);
    await new Promise(res => setTimeout(res, wait));
    return dbPost(q, attempt + 1);
  }
  if (!r.ok) throw Object.assign(new Error(`database ${r.status}: ${b.slice(0, 400)}`), { status: r.status, unsettled: r.status >= 500 });
  return JSON.parse(b);
}

// Which routines does this file define?
const uniq = [...new Set(
  [...sql.matchAll(/create\s+or\s+replace\s+function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi)].map(m => m[1].toLowerCase())
)];
if (!uniq.length && !DDL) {
  console.log('no functions defined in this file and --ddl not passed; nothing to do');
  process.exit(0);
}

// The shape of every table column and view in public, as one digest. A column that lands with a
// different type, a default that did not carry, or a view the planner expanded differently all
// change this; a row of DATA does not, which is the point.
const SHAPE = `select md5(string_agg(x, '|' order by x)) from (
  select 'c:'||table_name||'.'||column_name||':'||data_type||':'||is_nullable
         ||':'||coalesce(column_default,'-') x
    from information_schema.columns where table_schema='public'
  union all
  select 'v:'||viewname||':'||md5(definition) from pg_views where schemaname='public'
) s`;

const defsSql = () => `select p.proname n, pg_get_function_identity_arguments(p.oid) a,
  md5(p.prosrc) h, p.prosrc s
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname='public' and p.proname in (${uniq.map(n => `'${n}'`).join(',')})`;

// ================================================================================================
// GUARDS. All of them now run BEFORE the write. They used to run against the definitions read back
// from staging, i.e. after a harmless apply; with one project a guard that fires after the write
// has already let the thing it refuses into the database.
// ================================================================================================

// A FOREIGN OR DEAD PROJECT REF MUST NEVER BE APPLIED (12 Aug 2026, sharpened 15 Aug 2026).
//
// The original hazard: promoting a routine that hardcodes https://<staging-ref>.supabase.co
// silently repointed the PRODUCTION copy at STAGING, and nothing failed — production's trainer
// posted its work into the staging project and both sides kept reporting success. Nineteen routines
// carried one when that guard was written (fn_ai_trainer, fn_org_exec_knowledge_fill,
// fn_os_incident_open, fn_provision_category_call, fn_recert_rotate, fn_resilience_watch, fn_run_vt,
// fn_watch_failed_runs, fn_watch_health, qd_reveal_nudges, qd_sign_customer, qd_sign_supplier,
// run_agent, run_auto_deploy, run_doc_reminders, run_pending_digest, run_site_autodeploy,
// trg_autodispatch_inquiry, trg_enrich_capability).
//
// Since 15 Aug the hazard is WORSE, not gone. The staging project no longer exists, so a routine
// carrying its ref does not talk to the wrong database — it talks to nothing, and net.http_post
// records a failure the routine never reads. So this refuses any ref that is not this project's,
// and warns (does not refuse) on a literal of our own, which is merely brittle.
const REF_LITERAL = /https:\/\/([a-z]{20})\.supabase\.co/g;
const literals = [...new Set([...sql.matchAll(REF_LITERAL)].map(m => m[1]))];
const foreign = literals.filter(r => r !== PROD_REF);
if (foreign.length) {
  console.error('REFUSED: this file hardcodes a Supabase project ref that is not this project.');
  console.error(`  found: ${foreign.join(', ')}`);
  console.error(`  this project is ${PROD_REF}. pglpqrhvozwepymcuunn was DELETED on 15 Aug 2026:`);
  console.error('  a routine pointed at it fails silently inside net.http_post and reports success.');
  console.error("Fix: read app_secrets.project_ref inside the routine instead of writing the ref out.");
  process.exit(3);
}
if (literals.length) {
  console.log(`NOTE: this file writes its own project ref out as a literal (${literals.join(', ')}).`);
  console.log('      Prefer `select value from app_secrets where key = \'project_ref\'` — the pattern');
  console.log('      fn_action_invoke_dispatch, fn_rfq_redispatch_sweep and fn_capability_enrich_sweep use.');
}

// A BODY MAY NOT BE APPLIED AHEAD OF THE ROUTINE IT CALLS (14 Aug 2026).
//
// plpgsql resolves a callee at RUN time, so a routine calling public.fn_x() creates cleanly whether
// or not fn_x exists, every digest matches, and it throws the first time it is called.
//
// Nearly triggered on scripts/sql/org_reorg_04_runtime.sql: two sessions converged it and the
// merged version had fn_agent_context_v3 calling a new helper fn_task_tsquery that did not exist
// yet. Applying it would have made EVERY employee context assembly throw — the single hottest path
// in the company — while every check stayed green.
//
// project_parity would not have caught it either: that was a SHAPE check over columns and views,
// and a missing function is neither.
const CALLEE = /public\.((?:fn|trg|qd|run)_[a-z0-9_]+)\s*\(/g;
// A DROP names a routine that is meant to be gone afterwards, so it is not a call. Without this, a file
// that retires a routine could never be re-applied once the drop had run (14 Sep 2026, the loop file's
// drop of fn_it_engineer_handover_body refused its own idempotent re-apply).
const DROPPED_HERE = /drop\s+(?:function|procedure)\s+(?:if\s+exists\s+)?public\.[a-z0-9_]+\s*\(/gi;
const selfDefined = new Set(uniq);
const wanted = [...new Set([...sql.replace(DROPPED_HERE, '').matchAll(CALLEE)].map(m => m[1].toLowerCase()))]
  .filter(c => !selfDefined.has(c));
if (wanted.length) {
  const rows = await mgmtRead(PROD_REF, `select distinct lower(p.proname) n
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname='public' and lower(p.proname) in (${wanted.map(w => `'${w}'`).join(',')})`);
  const have = new Set(rows.map(r => r.n));
  // A TABLE NAMED LIKE A ROUTINE IS NOT A CALLEE (27 Oct 2026, it_engineer). `insert into public.fn_task_class (fn, …)`
  // matched CALLEE and refused the_portal_turn_has_its_task_class.sql (#1640) as "calls public.fn_task_class()", which
  // is a table. A name is excused only when it is an existing relation in public and no routine; a missing routine is
  // still refused exactly as before.
  const notFound = wanted.filter(w => !have.has(w));
  if (notFound.length) {
    const rels = await mgmtRead(PROD_REF, `select distinct lower(c.relname) n from pg_class c
        join pg_namespace ns on ns.oid = c.relnamespace
       where ns.nspname='public' and c.relkind in ('r','p','v','m','f')
         and lower(c.relname) in (${notFound.map(w => `'${w}'`).join(',')})`);
    for (const r of rels) have.add(r.n);
  }
  const missing = wanted.filter(w => !have.has(w));
  if (missing.length) {
    console.error('REFUSED: this file defines a routine that calls something the database does not have.');
    console.error('plpgsql resolves a callee at run time, so this would apply cleanly, match every');
    console.error('digest, and then throw the first time it ran.');
    for (const m of missing) console.error(`  missing on ${PROD_REF}: public.${m}()`);
    console.error('Fix: apply the file that DEFINES those routines first, then re-run this one.');
    process.exit(4);
  }
}

// ================================================================================================

// The body a file declares for each routine, between the first $tag$ after the header and its twin.
// Compared on TOKENS rather than bytes, the same normalisation sql_files_match_live.test.mjs uses,
// so that whitespace the server re-renders is not reported as a difference.
const tok = (s) => (String(s).match(/[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|'(?:[^']|'')*'|[^\sA-Za-z0-9_$]/g) || [])
  .join(' ').toLowerCase();
const declared = new Map();
{
  const re = /create\s+or\s+replace\s+function\s+(?:public\.)?([a-z0-9_]+)\s*\(/gi;
  let m;
  while ((m = re.exec(sql))) {
    const name = m[1].toLowerCase();
    const rest = sql.slice(m.index);
    // DIGITS BELONG IN A DOLLAR TAG. This was /\$[a-z_]*\$/, so every tag carrying a number —
    // $s3_cron$, $k3_step$, $v2$ — failed to match, the routine never entered `declared`, and the
    // read-back reported DIFFERS on six routines whose bodies were byte-identical to the file.
    // A guard that cries wolf is worse than no guard: the next real drift gets waved through as
    // "just the tag again". Found applying kernel_s3, 17 Aug 2026.
    const tag = rest.match(/as\s+(\$[a-z0-9_]*\$)/i);
    if (!tag) continue;
    const start = rest.indexOf(tag[1], rest.indexOf(tag[0])) + tag[1].length;
    const end = rest.indexOf(tag[1], start);
    if (end < 0) continue;
    if (!declared.has(name)) declared.set(name, []);
    declared.get(name).push(tok(rest.slice(start, end)));
  }
}

const { execSync } = await import('node:child_process');
// THE SEAT IS SIGNED TOO (22 Sep 2026, scripts/lib/apply_seat.mjs). No seat, no write to production.
const { seatFor, SEATS } = await import('./lib/apply_seat.mjs');
const git = (cmd) => { try { return execSync(cmd, { encoding: 'utf8' }).trim(); } catch { return ''; } };
const seatFlag = process.argv.includes('--seat') ? process.argv[process.argv.indexOf('--seat') + 1] : null;
const seat = seatFor({ flag: seatFlag, branch: git('git rev-parse --abbrev-ref HEAD'), subject: git('git log -1 --format=%s') });
if (!seat) {
  console.error(`REFUSED: no seat owns this apply. Name it with --seat <${SEATS.join('|')}>, or apply from a branch or`);
  console.error('commit that starts with the seat (it_engineer/..., "it_engineer: ..."). An unattributed routine change is a finding.');
  process.exit(2);
}

if (!APPLY) {
  console.log(`\nDRY RUN — nothing was written to ${PROD_REF}.`);
  console.log(`  ${file}`);
  console.log(`  defines ${uniq.length} routine(s): ${uniq.join(', ') || '(none)'}`);
  console.log(`  calls ${wanted.length} routine(s) it does not define; all present on the database`);
  if (DDL) console.log('  --ddl: also carries schema changes');
  console.log('  applied for the seat: ' + seat);
  // the limits the apply will set (guard fix round, item 4): the flag is read and checked here too, so a bad one fails the dry run
  // ... and what --apply would refuse is refused here too (review 2, items 2-3): a limit the file moves, dynamic SQL
  try {
    const g = await import('./lib/replay_guard.mjs');
    const lt = g.applyLockTimeout(process.argv.slice(3));
    g.tightenLimits(sql, file, { cap: lt });
    const dyn = g.dynamicSql(sql);
    if (dyn.length) throw new Error(`${file} runs dynamic SQL in a DO block (${dyn.slice(0, 3).map((d) => `line ${d.line} ${d.what}`).join('; ')}); --apply would refuse it`);
    console.log(`  --apply will set lock_timeout = ${lt} (the file's own lowered to it), and transaction_timeout = 60s if it takes a lock that stops writers`);
  } catch (e) { console.error('REFUSED: ' + e.message); process.exit(2); }
  console.log('\nGuards passed. Re-run with --apply to write it.');
  process.exit(0);
}

const shapeBefore = DDL ? one(await mgmtRead(PROD_REF, SHAPE)) : null;

// THE APPLY SIGNS ITS WRITE. public.routine_change_log records application_name for every routine
// change. Three times on 14 Sep 2026 a reviewed routine was rewritten seconds later by an older copy
// of its file from an unknown caller, logged only as 'mgmt-api'. Every apply from this tool now names
// its commit, working directory and file, so an untagged routine change is, by construction, not from
// a current checkout of this tool.
let rev = 'unknown';
try { rev = execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim(); } catch { /* not a git checkout */ }
// application_name holds 63 bytes, so keep the parts that identify a caller: commit, seat, the last
// folder of the working directory (the worktree name), and the start of the file name.
const base = (p) => String(p).split(/[\\/]/).filter(Boolean).pop() || '';
// Reduced to plain ASCII letters, digits, space, dot, dash and underscore, so the literal can never
// close its quotes and one character is one byte under the 63-byte limit.
// (the tag itself is built below as applyTag, with a nonce after the seat so a 5xx can find its own session)
// Same line as the file's first line, so reported line numbers still match the file. A file that
// must run outside a transaction (CREATE INDEX CONCURRENTLY) is sent alone: a second statement in
// the same query would wrap it in an implicit transaction and Postgres would refuse it.
// Statements only: a comment that mentions the word used to send a routine file unsigned.
const mustRunAlone = (await import('./lib/sql_text.mjs')).runsOutsideTransaction(sql);
// AN APPLY NEVER QUEUES EVERY READER BEHIND IT, AND NEVER HOLDS THEM FOR LONG (it_engineer, 13 Nov 2026; review item 4).
// An ALTER TABLE that waits for its lock blocks every later reader of that table until it gets it, and once it has it, it holds
// it until the file commits: on 13 Nov rehearsals that held quotes/inquiries for 12-15 s cancelled live requests at their 8 s
// limit (scripts/lib/replay_guard.mjs header). So, through the same limits as a replay:
//   * lock_timeout 1500 ms (--lock-timeout=<ms> to change, 1-15000), and the file's OWN lock_timeout is lowered to it too (it
//     used to override it: 3 s in two of this week's files, 15 s in one committed file), via replay_guard's tightenLimits, on
//     the same line; the apply prints the limits it set;
//   * a transaction_timeout of 60 s when any statement takes a lock that stops writers on a relation production has (read from
//     pg_class, once); a backfill that needs longer is split or applied in a quiet minute, never left to hold the table;
//   * a lock not granted rolls ALL of the one-transaction request back; it is retried after a FIXED 10 s pause, 5 times;
//   * a 5xx or a dropped connection is never re-sent: settleUnknown() says whether it committed (below), and it stops.
const guard = await import('./lib/replay_guard.mjs');
const { mgmtRead: readProd } = await import('./lib/qd_guard.mjs');
let text; let lockTimeout;
try {
  lockTimeout = guard.applyLockTimeout(process.argv.slice(3));
  text = guard.tightenLimits(sql, file, { cap: lockTimeout });
  // DYNAMIC SQL IS NOT APPLIED (review 2 of 13 Nov 2026, items 2-3): what an EXECUTE builds at run time cannot be read before it is
  // sent, neither its locks nor a limit it sets. Write the statements out (every overload of a revoke by its signature).
  const dynamic = guard.dynamicSql(sql);
  if (dynamic.length) throw new Error(`${file} runs dynamic SQL in a DO block (${dynamic.slice(0, 3).map((d) => `line ${d.line} ${d.what}`).join('; ')}): `
    + 'an EXECUTE whose argument is not one literal is never sent to production. Write the statements out, then apply.');
} catch (e) { console.error('REFUSED: ' + e.message); process.exit(2); }
const strongLocks = mustRunAlone ? [] : guard.stallsLiveUsers(sql, await guard.relationCatalogue((q) => readProd(PROD_REF, q)));
if (strongLocks.length) {
  console.log(`  takes a lock that stops writers on ${[...new Set(strongLocks.map((l) => l.table))].slice(0, 8).join(', ')}: `
    + `the apply is cut at ${guard.APPLY_HOLD_LIMIT} if it holds it longer`);
}
const nonce = Math.random().toString(16).slice(2, 8);
const applyTag = `qd-apply ${rev} ${seat} ${nonce} ${base(process.cwd())} ${base(file)}`.replace(/[^A-Za-z0-9 ._-]/g, '_').slice(0, 63);
const { prelude, said } = guard.applyPrelude({ lockTimeout, holdsStrongLock: strongLocks.length > 0, tag: applyTag });
if (!mustRunAlone) console.log(`  ${said}`);
else console.log('  limits set: none (the file runs alone, outside a transaction: CONCURRENTLY takes no lock that stops writers)');
const LOCK_NOT_GRANTED = /lock timeout|55P03/i;
const HOLD_CUT = /transaction timeout|25P04/i;

// WHAT THE DATABASE HOLDS OF THIS FILE: the bodies of the routines it defines and the public shape. A request is one
// transaction, so after an answer that proves nothing (5xx, dropped connection) this is how the applier learns whether it
// committed: all or nothing, so if any routine the file changes is unchanged, nothing of the file committed.
const stateNow = async () => {
  const defs = uniq.length ? await readProd(PROD_REF, defsSql()) : [];
  const shape = one(await readProd(PROD_REF, SHAPE));
  return { shape, defs: new Map(defs.map((r) => [`${r.n}(${r.a})`, tok(r.s)])) };
};
const differsFromFile = (state) => [...declared.entries()].some(([n, bodies]) => {
  const live = [...state.defs.entries()].filter(([k]) => k.startsWith(`${n}(`)).map(([, b]) => b);
  return !bodies.every((b) => live.includes(b));
});
const sameState = (a, b) => a.shape === b.shape && a.defs.size === b.defs.size && [...a.defs].every(([k, v]) => b.defs.get(k) === v);
const before = mustRunAlone ? null : await stateNow();

// HOW A 5xx IS SETTLED (decided 13 Nov 2026). 1) Wait until no session carries this apply's tag (its nonce makes it this
// apply's own): the first copy has ended, committed or not. 2) If what the file defines or shapes changed, it COMMITTED behind
// the error: go on to the read-back (its probe verdict was lost with the answer, so the exit says so). 3) If nothing changed AND
// the file was going to change something we can see (a routine whose live body differed from the file before the apply), the
// all-or-nothing transaction proves it did NOT commit: it stops, exit 4, and is NOT re-sent (item 5 of the guard fix round:
// a retry can double a held lock); the operator re-runs the command. 4) Otherwise (a re-apply of identical routines, DDL whose
// effect is not in the shape digest, data only) the applier cannot tell, so it does not guess: it stops, exit 5, and says how
// to check by hand. A file is never re-sent on the hope that it is idempotent.
// 5) The first copy still there after the wait: exit 5, STILL RUNNING, never judged (review 2, item 5). 6) Before anyone is told to
// re-run, the MANIFEST is read: a file it already lists was applied before, and a re-run is not the 5xx's decision.
async function settleUnknown(e) {
  let stillRunning = true;
  for (let i = 0; i < 40; i++) {
    const rows = await readProd(PROD_REF, `select count(*)::int as n from pg_stat_activity where application_name = '${applyTag}'`);
    if (!rows?.[0]?.n) { stillRunning = false; break; }
    console.log(`  the first copy is still running on production; waiting (${i + 1}/40)`);
    await new Promise((res) => setTimeout(res, 3000));
  }
  const verdict = stillRunning ? 'running' : guard.settleVerdict(sameState(before, await stateNow()) ? 'same' : 'changed', 'same', differsFromFile(before));
  let inManifest = true;   // unreadable: never tell anyone to re-run
  try { inManifest = readFileSync(new URL('./sql/MANIFEST.txt', import.meta.url), 'utf8').split('\n').some((l) => l.trim() === `scripts/sql/${base(file)}`); } catch { /* kept true */ }
  const out = guard.settleOutcome({ stillRunning, verdict, inManifest, file, tag: applyTag });
  if (out.exit === 0) return 'committed';
  console.error(`  (${String(e.message).slice(0, 200)})`);
  for (const l of out.lines) console.error(l);
  process.exit(out.exit);
}

let applied;
let verdictLost = false;
for (let attempt = 1; ; attempt++) {
  try {
    applied = await dbPost(mustRunAlone ? sql : prelude + text);
    break;
  } catch (e) {
    const msg = String(e?.message ?? e);
    if (!mustRunAlone && HOLD_CUT.test(msg)) {
      console.error(`REFUSED BY THE DATABASE: ${file} held a lock that stops writers for more than ${guard.APPLY_HOLD_LIMIT}, and the`);
      console.error('whole file was rolled back. Split its backfill, or apply it in a quiet minute with a smaller batch.');
      process.exit(6);
    }
    if (!mustRunAlone && e?.unsettled) {
      const verdict = await settleUnknown(e);
      // NEVER RE-SENT AFTER A 5xx (decided 13 Nov 2026, guard fix round, item 5): a second copy sent while the first may still be
      // ending doubles a held lock. settleUnknown has already stopped (exit 4 or 5) unless it committed.
      if (verdict === 'committed') { console.log(`  ${msg.slice(0, 120)}: it COMMITTED behind the error; reading it back`); applied = []; verdictLost = true; break; }
    }
    if (mustRunAlone || !LOCK_NOT_GRANTED.test(msg) || attempt >= 6) throw e;
    console.log(`  a lock was not granted within ${lockTimeout}; nothing was applied; retrying in 10s (attempt ${attempt}/5)`);
    await new Promise((res) => setTimeout(res, 10_000));
  }
}
console.log(`applied ${file} to ${PROD_REF}`);

// A PROBE THAT CANNOT REPORT IS NOT A PROBE.
//
// apply-discipline §4 is right that a file carrying DDL must not `raise exception` from its probe —
// the raise would roll back the DDL in its own file, which happened twice. What it prescribed
// instead, `raise notice`, prints NOWHERE. MEASURED 18 Sep 2026 against this project:
//
//     do $$ begin raise notice 'a verdict'; end $$;                  -> body []
//     do $$ begin raise notice 'a verdict'; end $$; select 1 as a;   -> body [{"a":1}]
//     raise warning instead of notice                                -> body [{"a":1}]
//     set client_min_messages to notice; … same DO block …           -> body [{"a":1}]
//     select name, setting from pg_settings                          -> log_min_messages = warning
//
// The management API discards NOTICE and WARNING alike, and this tool had no handling for either
// (`grep -n NOTICE scripts/apply_sql.mjs` returned nothing before today). `psql` is not installed
// and no direct connection string exists in the environment or in supabase/config.toml, so the
// applier has exactly TWO channels: a RESULT SET, and an ERROR. An error is what §4 forbids. That
// leaves the result set, and nothing was reading it — `await dbPost(...)` threw the rows away.
//
// So the convention is the channel that exists: a probe's LAST statement is a plain SELECT whose
// value begins with the OK marker or the FAILED marker below, and this reads it. A FAILED verdict
// is counted into `bad`, so the exit code is non-zero even though the DDL applied — which is the
// honest outcome: the change is live and its verification did not pass. Say so rather than printing
// a success line over an unverified apply.
//
// Chosen over two alternatives, on this evidence. Writing the verdict to a ROW would need a new
// table and would defer the finding to whenever some later check happens to run, while this fires
// at the moment of the apply. Splitting every such file into DDL plus a separate pure-probe file
// that MAY raise would double the files and the MANIFEST lines and move the forgettable step from
// "a notice nobody reads" to "a second file nobody applies".
//
// scripts/checks/a_probe_that_cannot_report_is_not_a_probe.test.mjs keeps the blind spot from
// growing back, and records the files measured today that predate the convention.
const PROBE_OK = 'PROBE OK';
const PROBE_FAILED = 'PROBE FAILED';
let probeFailures = 0;
let probeVerdicts = 0;
for (const row of Array.isArray(applied) ? applied : []) {
  for (const cell of Object.values(row || {})) {
    if (typeof cell !== 'string') continue;
    const v = cell.trim();
    if (v.startsWith(PROBE_OK)) { probeVerdicts++; console.log(`PROBE   ${v.slice(0, 500)}`); }
    else if (v.startsWith(PROBE_FAILED)) { probeVerdicts++; probeFailures++; console.error(`PROBE   ${v.slice(0, 500)}`); }
  }
}

// AND A PROBE THAT RETURNS NOTHING IS NOT A PASS. This is the same defect one layer up, and it is
// worth closing here rather than in each file, because every file that adopts the convention
// inherits it. Found in review of this change, in the file that introduced the convention:
//
//   * that file is an ALTER, so it defines no routine, so `uniq` is empty and the read-back loop
//     below never runs — the probe is its ONLY verification;
//   * a probe written as `select … from pg_proc where proname = '…'` returns ZERO ROWS if the
//     routine is absent or renamed, rather than an error;
//   * zero rows means no verdict, and the success line at the end of this file does not depend on
//     one, so the apply printed "read back and identical to the file" having checked nothing.
//
// A file whose SOURCE carries a verdict marker has promised a verdict. If none came back, either
// the probe matched nothing, or it was not the last row-producing statement in the file (the
// management API returns only the last result set), or somebody deleted it and left the marker in a
// comment. All three are the same thing from here: unverified. Anchored on the file's own text, so
// a file with no probe at all is not accused of losing one.
// Only CODE promises a verdict: a marker inside an SQL comment is prose. 29 Sep 2026, #1036's file said
// "must print PROBE OK" in a comment about its separate probe file, and a live, correct apply was
// reported as failed. Same stripping as a_probe_that_cannot_report_is_not_a_probe.test.mjs.
const sqlCode = sql.replace(/\/\*[\s\S]*?\*\//g, ' ').split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const promisesAVerdict = sqlCode.includes(PROBE_OK) || sqlCode.includes(PROBE_FAILED);
if (promisesAVerdict && probeVerdicts === 0) {
  if (verdictLost) console.error('PROBE   the answer that carried the verdict was lost to the 5xx above; the file committed.');
  probeFailures++;
  console.error(`PROBE   ${PROBE_FAILED}: ${file} contains a verdict marker and the apply returned no `
    + 'verdict. Nothing was verified. Either the probe query matched no rows, or it is not the last '
    + 'row-producing statement in the file — only the last result set comes back.');
}

// READ THE DEFINITIONS BACK OUT. This is the founder's rule, and it is the only reason the exit
// code below is worth anything: a 200 from the management API says the statement was accepted, not
// that the routine the file describes is the routine the database now holds.
const live = uniq.length ? await mgmtRead(PROD_REF, defsSql()) : [];
const byName = new Map();
for (const row of live) {
  if (!byName.has(row.n)) byName.set(row.n, []);
  byName.get(row.n).push(row);
}

let bad = 0;
for (const name of uniq) {
  const rows = byName.get(name);
  if (!rows || !rows.length) {
    bad++;
    console.log(`ABSENT  ${name}  — the file defines it and the database does not have it`);
    continue;
  }
  const bodies = declared.get(name) || [];
  // Overloads: the file may define one signature of several. A match against ANY live body is the
  // honest test, and the identity arguments of every live overload are printed either way.
  const ok = !bodies.length || rows.some(r => bodies.includes(tok(r.s)));
  if (!ok) bad++;
  for (const r of rows) console.log(`${ok ? 'LIVE   ' : 'DIFFERS'} ${name}(${r.a})  md5 ${r.h}`);
}

if (DDL) {
  const shapeAfter = one(await mgmtRead(PROD_REF, SHAPE));
  console.log(shapeBefore === shapeAfter
    ? `SHAPE   public schema unchanged by this file (${shapeAfter}) — idempotent re-apply, or the DDL did nothing`
    : `SHAPE   public schema changed  ${shapeBefore} -> ${shapeAfter}`);
}

if (bad) {
  console.error(`\n${bad} routine(s) are not what ${file} says they are. The apply reported success `
    + 'and the database disagrees; do not assume the file is what is running.');
  process.exit(1);
}
// A FAILED PROBE IS NOT A ROUTINE MISMATCH, so it gets its own words and its own exit code. The DDL
// is applied and live; what did not pass is the file's own verification of it.
if (probeFailures) {
  console.error(`\n${probeFailures} probe verdict(s) in ${file} reported FAILED. The statements were `
    + 'applied and are live — this is not a half-applied database — but the file\'s own check of '
    + 'what it just did did NOT pass. Read the PROBE line above before treating this apply as done.');
  process.exit(3);
}
console.log(`\nAPPLIED ${uniq.length} routine(s)${DDL ? ' + DDL' : ''} to ${PROD_REF}, read back and identical to the file`);
