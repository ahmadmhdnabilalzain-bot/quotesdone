// THE ONE REFUND RAIL LEAVES NO RESIDUE (15 Sep 2026, agent: accountant).
//
// Re-read of docs/audit/BACKEND_AUDIT_AND_ONE_YEAR_PLAN_2026-09-14.md after the refund path became
// one rail (public.refunds -> CEO -> accountant). Four leftovers, each asserted here:
//   1. The supplier non-response charge is raised by the rail itself: supplier_dues has ONE writer,
//      fn_accountant_raise_nonresponse_charge, reached from fn_accountant_refund_settled via the
//      transactions trigger z40_refund_outcome_follows_through. qd_on_refund_resolved stays gone.
//   2. fn_gl_post refuses any journal that is not a draft (scripts/sql/only_a_draft_journal_can_be_posted.sql).
//   3. The customer's reveal document never makes a second invoice number (reveal_invoice).
//   4. Control Mode is retired with its template row and its minutes secret
//      (scripts/sql/control_mode_is_retired_with_its_template_and_its_minutes.sql).
// Production reads skip without a management token (CI's checks job has none).
//
//   node --test scripts/checks/the_refund_rail_leaves_no_residue.test.mjs
import { SUPABASE_TOKEN_FILE } from '../lib/supabase_token.mjs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { sql } from '../lib/db.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(root, p), 'utf8');
const LOCAL_TOKEN = SUPABASE_TOKEN_FILE;
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || (existsSync(LOCAL_TOKEN) ? readFileSync(LOCAL_TOKEN, 'utf8') : '')).trim();
// The same backoff-less transport that turned five other checks red on the throttled night of
// 22 Sep 2026 (see a_reversed_supplier_charge_is_never_owed.test.mjs). This one happened not to be
// running at the time; the defect is the transport, not the hour, so it is corrected with its
// siblings. scripts/lib/db.mjs is the estate's one retry policy for this endpoint; `readOnly`
// keeps the read_only flag this check has always set.
const q = (query) => sql(query, { readOnly: true });
const edgeSources = () => readdirSync(join(root, 'supabase', 'functions'), { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .flatMap((d) => readdirSync(join(root, 'supabase', 'functions', d.name))
    .filter((f) => f.endsWith('.ts')).map((f) => [d.name + '/' + f, read(`supabase/functions/${d.name}/${f}`)]));

test('the non-response charge is raised by the rail; the old trigger function stays gone', async (t) => {
  assert.match(read('supabase/functions/refunds_api/index.ts'), /'resolve' is RETIRED \(410\)/);
  assert.deepEqual(edgeSources().filter(([, s]) => s.includes('qd_on_refund_resolved')).map(([n]) => n), []);
  if (!token) { t.skip('no management token'); return; }
  const [row] = await q(`select
      (select count(*) from pg_proc where proname = 'qd_on_refund_resolved')::int as old_fn,
      (select json_agg(p.proname order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.prosrc ~* 'insert\\s+into\\s+(public\\.)?supplier_dues') as dues_writers,
      (select p.prosrc like '%fn_accountant_raise_nonresponse_charge%' from pg_proc p where p.proname = 'fn_accountant_refund_settled') as settled_raises,
      (select p.prosrc like '%fn_accountant_refund_settled%' from pg_proc p where p.proname = 'fn_transaction_refund_outcome_follows_through') as trigger_fn_settles,
      exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
               where t.tgrelid = 'public.transactions'::regclass and p.proname = 'fn_transaction_refund_outcome_follows_through'
                 and t.tgenabled <> 'D') as attached`);
  assert.equal(row.old_fn, 0);
  assert.deepEqual(row.dues_writers, ['fn_accountant_raise_nonresponse_charge']);
  assert.equal(row.settled_raises, true);
  assert.equal(row.trigger_fn_settles, true);
  assert.equal(row.attached, true);
});

test('fn_gl_post refuses unless the journal is a draft, in whichever file is the last in the apply order', () => {
  // 29 Sep 2026: #1063 (the_accountant_books_a_late_item_as_a_prior_period_adjustment.sql) redefined fn_gl_post
  // with the prior-period move and kept the refusal. The rule is the refusal in the CANONICAL body, not a file name.
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql'));
  const defining = manifest.filter((p) => existsSync(join(root, p)) && /function\s+public\.fn_gl_post\s*\(/i.test(read(p)));
  assert.ok(defining.length, 'no file in MANIFEST defines fn_gl_post');
  const src = read(defining.at(-1));
  const body = src.slice(src.search(/function\s+public\.fn_gl_post\s*\(/i));
  assert.match(body, /if\s+[\w.]+\s+is\s+distinct\s+from\s+'draft'\s+then\s+raise\s+exception/i,
    `${defining.at(-1)} (the canonical fn_gl_post) must refuse any journal that is not a draft`);
});

test('the reveal receipt makes no invoice number of its own', () => {
  const s = read('supabase/functions/reveal_invoice/index.ts');
  assert.doesNotMatch(s, /'QD-INV-'/);
  // 21 Sep 2026: the number printed is Stripe's (reveal_fee_documents.ts docRef), never one made here.
  assert.match(read('supabase/functions/_shared/reveal_fee_documents.ts'), /return s\.invoice_no \|\| s\.payment_ref;/);
});

test('Control Mode is retired: no live code names it, and the retirement is recorded', () => {
  const offenders = edgeSources().filter(([, s]) => /fn_control_mode_require|fn_phase1_disarmed|control_mode_minutes/.test(s)).map(([n]) => n);
  assert.deepEqual(offenders, []);
  const dropped = read('scripts/sql/DROPPED.txt');
  for (const n of ['fn_control_mode_require', 'fn_phase1_disarmed']) assert.match(dropped, new RegExp('^' + n + ' :: dropped 15 Sep 2026', 'm'));
  const sql = read('scripts/sql/control_mode_is_retired_with_its_template_and_its_minutes.sql');
  assert.match(sql, /drop function if exists public\.fn_control_mode_require\(text, text\);/);
  assert.match(sql, /drop function if exists public\.fn_phase1_disarmed\(\);/);
  assert.match(sql, /delete from public\.messaging_template\s+where template_key = 'control_mode_code' and lang = 'en' and channel = 'whatsapp' and status = 'rejected';/);
  assert.match(sql, /delete from public\.app_secrets where key = 'control_mode_minutes';/);
});
