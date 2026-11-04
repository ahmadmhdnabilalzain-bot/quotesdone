// scripts/e2e/founder_command_channel_sql.mjs — the founder command channel's SQL routines, run for real, on a throwaway
// local Postgres that this script creates and deletes. Release qualification gap #10 (F07.02-F07.05), 3 Nov 2026.
// Assigned: ceo (who may command the company, and what he may change by text) + customer_support (the WhatsApp seat).
//
//   node scripts/e2e/founder_command_channel_sql.mjs        (needs PostgreSQL server binaries: initdb, pg_ctl, psql)
//
// WHY A LOCAL POSTGRES. supabase/functions/wa_inbound/founder_command_channel.test.ts drives the real wa_inbound handler
// with signed Twilio requests, but its database is a stub. The routines that decide WHO the founder is and WHAT a text may
// change are SQL, so they are proved here on their own canonical bodies, read from scripts/sql at run time:
//   fn_identify_contact      the previous canonical body (known-bad control) and the fixed one
//   fn_founder_settings      scripts/sql/the_founder_can_change_things_by_text.sql (the registry)
//   fn_founder_apply_setting the same file (type, bounds, refusal by name, founder_directive audit, agent_runs)
//
// IT CANNOT REACH PRODUCTION OR A PERSON. It reads no credential and no environment database URL; the server it starts
// listens on a Unix socket inside its own temporary directory (listen_addresses = ''), and every psql call names that
// socket. PG* variables are removed from the child environment so nothing can redirect a call. The founder is a fixture
// in the reserved block (+971 50 000 00xx) registered in this throwaway database only; the real founder number appears
// nowhere. Nothing is sent: there is no network code in this file.
import { spawnSync } from 'node:child_process';
import { chownSync, existsSync, mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const RUN_TAG = 'founderchan-sql-' + Math.random().toString(36).slice(2, 10);
const two = (n) => String(n).padStart(2, '0');
const h = [...RUN_TAG].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7);
const NINE = '5000000' + two(60 + (h % 20));            // the national part of the fixture founder
const FOUNDER = '+971' + NINE;
const STRANGER = '+9715000000' + two(80 + (h % 10));
const SAME_NINE_ABROAD = '+966' + NINE;                 // a different country, the same nine digits

function pgBin() {
  const tryDir = (d) => d && existsSync(join(d, 'initdb')) && existsSync(join(d, 'pg_ctl')) ? d : null;
  const cfg = spawnSync('pg_config', ['--bindir'], { encoding: 'utf8' });
  const fromCfg = cfg.status === 0 ? tryDir(cfg.stdout.trim()) : null;
  if (fromCfg) return fromCfg;
  const base = '/usr/lib/postgresql';
  if (existsSync(base)) for (const v of readdirSync(base).sort().reverse()) { const d = tryDir(join(base, v, 'bin')); if (d) return d; }
  const which = spawnSync('sh', ['-c', 'command -v initdb'], { encoding: 'utf8' });
  if (which.status === 0) return tryDir(which.stdout.trim().replace(/\/initdb$/, ''));
  return null;
}

const BIN = pgBin();
if (!BIN) { console.error('REFUSED: no PostgreSQL server binaries (initdb, pg_ctl) found; this proof needs a local Postgres.'); process.exit(2); }
const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('PG') && k !== 'DATABASE_URL'));
const DIR = mkdtempSync(join(tmpdir(), 'qd-founderchan-'));
const DATA = join(DIR, 'data');
// initdb refuses to run as root (cloud sessions are root): the server is then run as an unprivileged local account.
const idOf = (u) => { const r = spawnSync('id', ['-u', u], { encoding: 'utf8' }); const g = spawnSync('id', ['-g', u], { encoding: 'utf8' }); return r.status === 0 ? [Number(r.stdout), Number(g.stdout)] : null; };
const AS = process.getuid?.() === 0 ? (['postgres', 'nobody'].map((u) => [u, idOf(u)]).find(([, i]) => i) ?? null) : null;
if (process.getuid?.() === 0 && !AS) { console.error('REFUSED: running as root and no unprivileged account (postgres, nobody) to run the server as.'); process.exit(2); }
if (AS) chownSync(DIR, AS[1][0], AS[1][1]);
const spawnAs = (bin, args, opts) => AS ? spawnSync('runuser', ['-u', AS[0], '--', bin, ...args], opts) : spawnSync(bin, args, opts);
const run = (cmd, args, input) => {
  const r = spawnAs(join(BIN, cmd), args, { encoding: 'utf8', env, input, maxBuffer: 16 << 20 });
  if (r.status !== 0) throw new Error(cmd + ' failed: ' + (r.stderr || r.stdout).slice(0, 2000));
  return r.stdout;
};
const psqlBin = existsSync(join(BIN, 'psql')) ? 'psql' : null;
const sql = (q) => {
  const r = spawnAs(psqlBin ? join(BIN, 'psql') : 'psql', ['-h', DIR, '-U', 'postgres', '-d', 'postgres', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1'],
    { encoding: 'utf8', env, input: q, maxBuffer: 16 << 20 });
  if (r.status !== 0) throw new Error('psql: ' + (r.stderr || r.stdout).slice(0, 2000));
  return r.stdout.trim();
};

// The one canonical body of a routine in a file: from its CREATE OR REPLACE to the closing dollar tag.
function bodyOf(file, routine) {
  const src = readFileSync(file, 'utf8');
  const at = src.search(new RegExp('create\\s+or\\s+replace\\s+function\\s+(?:public\\.)?' + routine + '\\s*\\(', 'i'));
  if (at < 0) throw new Error(routine + ' is not defined in ' + file);
  const tail = src.slice(at);
  const tag = tail.match(/\bas\s+(\$[a-z_]*\$)/i)[1];
  const open = tail.indexOf(tag);
  return tail.slice(0, tail.indexOf(tag, open + tag.length) + tag.length) + ';\n';
}

// The canonical file for a routine is the LAST one in scripts/sql/MANIFEST.txt that defines it (the apply order).
function canonicalFile(routine) {
  const files = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  const def = new RegExp('create\\s+or\\s+replace\\s+function\\s+(?:public\\.)?' + routine + '\\s*\\(', 'i');
  let last = null;
  for (const f of files) { try { if (def.test(readFileSync(f, 'utf8'))) last = f; } catch { /* listed, not on disk: the manifest check owns that */ } }
  return last;
}

const results = [];
const check = (name, ok, detail = '') => { results.push({ name, ok }); console.log((ok ? 'PASS ' : 'FAIL ') + name + (ok ? '' : '  ' + detail)); };
const j = (q) => JSON.parse(sql(q) || 'null');

try {
  run('initdb', ['-D', DATA, '-U', 'postgres', '--auth=trust', '-E', 'UTF8', '--no-locale']);
  run('pg_ctl', ['-D', DATA, '-o', `-c listen_addresses='' -k ${DIR} -c fsync=off`, '-l', join(DIR, 'log'), '-w', 'start']);

  // The tables the routines read and write, in the columns they use. Nothing else from production is needed or copied.
  sql(`create role anon; create role authenticated;
    create table public.app_secrets (key text primary key, value text, updated_at timestamptz default now());
    create table public.decision_policy (key text primary key, value jsonb, updated_at timestamptz default now());
    create table public.agent_runs (id bigserial primary key, agent text, status text, counts jsonb, note text, started_at timestamptz, finished_at timestamptz);
    create table public.leads (id bigint primary key, company_name text, claimed boolean, approval_status text);
    create table public.customers (id uuid primary key, full_name text);
    -- no supplier or customer owns any number in this database
    create function public.fn_whatsapp_owner(p_phone text, p_all boolean default false)
      returns table(party_kind text, customer_id uuid, lead_id bigint) language sql stable as $$ select null::text, null::uuid, null::bigint where false $$;`);
  sql(`insert into public.app_secrets(key, value) values
    ('admin_mfa_phone', '${FOUNDER}'), ('admin_emails', 'zz.founder.${RUN_TAG}@example.invalid'),
    ('invite_daily_cap','20'), ('invite_max_bounce_rate','0.05'), ('invite_enabled','true'), ('invite_target_per_category','10'),
    ('supplier_emails_enabled','true'), ('email_enabled','true'), ('wa_daily_cap','100'), ('wa_per_recipient_24h','3'), ('wa_autoreply_enabled','true'),
    ('supplier_outreach_golive','false'), ('marketing_golive','false'), ('stripe_live_enabled','false');
    insert into public.decision_policy(key, value) values
    ('workflow_reflection_steps_per_day','20'), ('cos_reflection_tasks_per_day','10'), ('match_max_fanout','8'), ('match_max_fanout_per_trade','4'),
    ('match_relevance_floor','40'), ('confidence_min','0.7'), ('matching_strike_limit','3'), ('auto_action_max_aed','0');`);

  // ---- WHO IS THE FOUNDER ----------------------------------------------------------------------------------------------
  const PREVIOUS = 'scripts/sql/the_whatsapp_number_is_confirmed_and_only_a_confirmed_one_is_used.sql';
  const FIXED = 'scripts/sql/the_founder_is_recognised_by_his_whole_number_not_its_last_nine_digits.sql';
  const who = (p) => j(`select public.fn_identify_contact('${p}')::text`)?.audience;
  sql(bodyOf(PREVIOUS, 'fn_identify_contact'));
  check('known-bad control: the previous body answers the same nine digits under +966 as the founder', who('whatsapp:' + SAME_NINE_ABROAD) === 'founder', String(who('whatsapp:' + SAME_NINE_ABROAD)));
  sql(readFileSync(FIXED, 'utf8'));
  for (const [label, p] of [['whatsapp:+971…', 'whatsapp:' + FOUNDER], ['+971…', FOUNDER], ['00971…', '00971' + NINE], ['05… (UAE local)', '0' + NINE], ['5… (UAE national)', NINE]]) {
    check('the fixture founder is the founder written as ' + label, who(p) === 'founder', String(who(p)));
  }
  check('the same nine digits under +966 are NOT the founder', who('whatsapp:' + SAME_NINE_ABROAD) === 'unknown', String(who('whatsapp:' + SAME_NINE_ABROAD)));
  check('another fixture number is not the founder', who('whatsapp:' + STRANGER) === 'unknown');
  check('the founder is named by the fixture address, never a real one', j(`select public.fn_identify_contact('whatsapp:${FOUNDER}')::text`)?.name === `zz.founder.${RUN_TAG}@example.invalid`);
  sql(`update public.app_secrets set value = '' where key = 'admin_mfa_phone'`);
  check('with no number registered for the run, nobody is the founder', who('whatsapp:' + FOUNDER) === 'unknown');
  sql(`update public.app_secrets set value = '+971 50 000, ${FOUNDER}' where key = 'admin_mfa_phone'`);
  check('a short entry in the list is ignored and the registered one still counts', who('whatsapp:' + FOUNDER) === 'founder' && who('whatsapp:+97150000') === 'unknown');

  // ---- WHAT A TEXT MAY CHANGE ------------------------------------------------------------------------------------------
  const SETTINGS = canonicalFile('fn_founder_settings');
  if (SETTINGS !== canonicalFile('fn_founder_apply_setting')) throw new Error('fn_founder_settings and fn_founder_apply_setting are canonical in different files');
  sql(readFileSync(SETTINGS, 'utf8'));
  const keys = sql(`select string_agg(setting_key, ',' order by setting_key) from public.fn_founder_settings()`).split(',');
  check('the registry has rows (' + keys.length + ')', keys.length >= 10);
  check('no go-live switch, Stripe, refund, payment or auto_action_max_aed key is in the registry', keys.every((k) => !/golive|go_live|stripe|refund|payment|auto_action_max_aed|price|fee/i.test(k)), keys.join(','));
  const apply = (k, v, inbound) => j(`select public.fn_founder_apply_setting('${k.replace(/'/g, "''")}', '${v}', '${inbound.replace(/'/g, "''")}', 'zz.founder.${RUN_TAG}@example.invalid', 'whatsapp')::text`);
  const secret = (k) => sql(`select value from public.app_secrets where key = '${k}'`);
  const lastDirective = () => j(`select row_to_json(d)::text from public.founder_directive d order by id desc limit 1`);

  let r = apply('invite_daily_cap', '30', 'Set the daily invitation cap to 30');
  let d = lastDirective();
  check('a registry change is applied and reports old and new', r.ok === true && r.old === '20' && r.new === '30', JSON.stringify(r));
  check('the setting really changed', secret('invite_daily_cap') === '30');
  check('it is audited in founder_directive (applied, old, new, the words, the actor)', d.applied === true && d.old_value === '20' && d.new_value === '30' && d.inbound === 'Set the daily invitation cap to 30' && d.actor.endsWith('@example.invalid'), JSON.stringify(d));
  check('and in agent_runs', sql(`select count(*) from public.agent_runs where agent = 'founder_directive' and counts->>'key' = 'invite_daily_cap'`) === '1');
  r = apply('match_max_fanout', '12', 'match up to 12 suppliers');
  check('a decision_policy number stays a jsonb number', r.ok === true && sql(`select jsonb_typeof(value) || ':' || value::text from public.decision_policy where key = 'match_max_fanout'`) === 'number:12');
  r = apply('invite_enabled', 'off', 'stop the invites');
  check('a switch accepts off', r.ok === true && secret('invite_enabled') === 'false');
  r = apply('invite_enabled', 'off', 'stop the invites');
  check('the same value again changes nothing and says so', r.ok === true && r.unchanged === true && lastDirective().applied === false);

  for (const [k, v, words, store] of [
    ['Stripe live payments', 'on', 'Turn on Stripe live payments', null],
    ['stripe_live_enabled', 'true', 'enable stripe live', 'stripe_live_enabled'],
    ['supplier_outreach_golive', 'on', 'switch supplier outreach go live on', 'supplier_outreach_golive'],
    ['marketing_golive', 'on', 'go live with marketing', 'marketing_golive'],
    ['auto_action_max_aed', '50000', 'Raise auto_action_max_aed to 50000', 'auto_action_max_aed'],
    ['automatic refund approval', 'on', 'Approve refunds automatically', null],
  ]) {
    const before = store ? (store === 'auto_action_max_aed' ? sql(`select value::text from public.decision_policy where key = '${store}'`) : secret(store)) : null;
    r = apply(k, v, words); d = lastDirective();
    const after = store ? (store === 'auto_action_max_aed' ? sql(`select value::text from public.decision_policy where key = '${store}'`) : secret(store)) : null;
    check(`forbidden "${k}" is refused by name and not applied`, r.ok === false && /cannot change "/.test(r.refusal) && r.refusal.includes(k), JSON.stringify(r));
    check(`forbidden "${k}" is audited as refused`, d.applied === false && d.setting_key === k && d.refusal === r.refusal);
    if (store) check(`forbidden "${k}" left its value as it was`, before === after, before + ' -> ' + after);
  }
  r = apply('wa_daily_cap', '5000', 'whatsapp cap 5000');
  check('above the ceiling is refused with the bound', r.ok === false && /ceiling of 500/.test(r.refusal) && secret('wa_daily_cap') === '100', JSON.stringify(r));
  r = apply('invite_daily_cap', '2.5', 'cap 2.5');
  check('a fraction for a whole-number setting is refused', r.ok === false && secret('invite_daily_cap') === '30');
  r = apply('invite_daily_cap', 'thirty; drop table app_secrets', 'injection');
  check('text in a number setting is refused and nothing is executed', r.ok === false && sql(`select to_regclass('public.app_secrets') is not null`) === 't');
} catch (e) {
  check('the run completed', false, String(e?.message || e).slice(0, 1500));
} finally {
  try { run('pg_ctl', ['-D', DATA, '-m', 'immediate', '-w', 'stop']); } catch { /* already down */ }
  rmSync(DIR, { recursive: true, force: true });
}
const failed = results.filter((x) => !x.ok).length;
console.log(`VERDICT ${failed ? 'FAILED' : 'OK'}: ${results.length - failed}/${results.length} checks passed (run tag ${RUN_TAG}; throwaway database deleted)`);
process.exit(failed ? 1 : 0);
