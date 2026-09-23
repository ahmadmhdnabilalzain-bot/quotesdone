// NO REVIEW CLASS CAN ROUTE TO ITS AUTHOR'S FAMILY (23 Sep 2026, it_engineer; founder instruction ~891).
//
// Whenever one seat or step reviews, judges, verifies, compares or approves another's model output, the two
// must never be on the same LLM family. scripts/sql/every_review_class_is_judged_by_another_family_than_its_author.sql
// declares the pairs (model_policy.reviews_class) and routes every review through fn_ai_route_review.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   static (always):
//     * a known review class is dropped from the declaration, or declared with no author class;
//     * an edge function calls a review class (by task_class or by an fn that fn_task_class maps to one)
//       without naming counterpart_model;
//     * ai_gateway stops refusing a review class that names no counterpart, or stops writing the counterpart
//       into the log line the DB backstop reads;
//   production (needs a management token; ONE aborted transaction, the SQL files replayed first when they are
//   not applied yet, so nothing survives):
//     * for ANY review class R, ANY author class A it judges, and EACH of A's primary and fallback models m:
//       the route the gateway would take (fn_ai_route_review when R is declared, fn_ai_route when it is not)
//       gives R no model, or a primary OR a fallback of m's family;
//     * the redaction verify has no third-family fallback;
//     * ai_cost_log holds a flagged review call (review_violation) in the last 30 days.
//
// PROOF IT FAILS ON THE POLICY BEFORE THE FILE: XFAM_NO_REPLAY=1 evaluates production exactly as it is, with no
// file replayed. Before the file is applied that run fails (quote_comparison Sol over document_extraction Sol, ...).
//
//   node --test scripts/checks/no_review_class_can_route_to_its_authors_family.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/every_review_class_is_judged_by_another_family_than_its_author.sql';
const BASE = 'scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql';

// Every review-shaped class the audit of 23 Sep 2026 found. Adding one is allowed; dropping one fails.
const REQUIRED = ['ceo_judgement', 'ceo_approval_decision', 'identity_redaction_verify', 'quote_comparison',
  'drawing_boq_confirm', 'knowledge_validation', 'seat_deliberation_blind', 'seat_deliberation_compare'];
// The functions fn_task_class maps onto a review class (production, 23 Sep 2026).
const REVIEW_FNS = { quote_compare: 'quote_comparison', quote_review: 'quote_comparison',
  drawing_redact_verify: 'identity_redaction_verify', ceo_agent: 'ceo_judgement' };

function declared() {
  const sql = read(FILE);
  const block = sql.slice(sql.indexOf('update public.model_policy set reviews_class'), sql.indexOf(') as v(task_class, authors)'));
  const out = {};
  for (const m of block.matchAll(/\('([a-z_]+)',\s*array\[([^\]]*)\]\)/g)) out[m[1]] = [...m[2].matchAll(/'([a-z_0-9]+)'/g)].map((x) => x[1]);
  return out;
}

function walk(dir) {
  const out = [];
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (/\.ts$/.test(n) && !/\.test\.ts$/.test(n)) out.push(p);
  }
  return out;
}

test('every review class is declared with the author classes it judges', () => {
  const d = declared();
  for (const c of REQUIRED) assert.ok(Array.isArray(d[c]) && d[c].length > 0, `${c} must declare reviews_class`);
  assert.deepEqual(d.identity_redaction_verify, ['document_extraction']);
  assert.deepEqual(d.quote_comparison, ['document_extraction']);
  assert.match(read(FILE), /set model_fallback = 'google\/gemini-3\.8-flash'[\s\S]*where task_class = 'identity_redaction_verify'/,
    'the redaction verify keeps a third-family fallback');
});

test('the gateway refuses a review class without its author, and writes the author where the backstop reads it', () => {
  const gw = read('supabase/functions/ai_gateway/index.ts');
  assert.match(gw, /from\('model_policy'\)\.select\('reviews_class'\)/);
  assert.match(gw, /outcome: 'review_needs_counterpart'/);
  assert.match(gw, /route\.why = String\(route\.why \?\? ''\) \+ ' \| counterpart_model=' \+/);
  assert.match(gw, /counterpart \? 0 : Number\(body\.cache_ttl_min/, 'a review is never served from cache');
  const sql = read(FILE);
  assert.match(sql, /substring\(coalesce\(new\.model_selected_because, ''\) from 'counterpart_model=\(\[\^ \|\]\+\)'\)/);
});

test('every edge function that calls a review class names counterpart_model', () => {
  const offenders = [];
  const classes = REQUIRED.join('|');
  for (const f of walk(join(REPO, 'supabase', 'functions'))) {
    const rel = relative(REPO, f).replace(/\\/g, '/');
    if (rel.startsWith('supabase/functions/ai_gateway/')) continue;
    const src = readFileSync(f, 'utf8');
    const hits = [
      ...src.matchAll(new RegExp(`(?:task_class|taskClass)\\s*:\\s*'(${classes})'`, 'g')),
      ...src.matchAll(new RegExp(`\\bfn\\s*:\\s*'(${Object.keys(REVIEW_FNS).join('|')})'`, 'g')),
      ...src.matchAll(/task_class\s*:\s*CONFIRM_ROUTE/g),
    ];
    for (const h of hits) {
      // The call that carries this class: the statement around it (a fetch body, or the makeLlmRich + its call).
      const win = src.slice(Math.max(0, h.index - 200), h.index + 1200);
      if (!/counterpart_model\s*:|counterpartModel\s*:/.test(win)) offenders.push(`${rel}: ${h[0]}`);
    }
  }
  assert.deepEqual(offenders, [], 'a review call names no author model');
  // "The author is code" is never hard-coded at a review call: it must come from the author's own record.
  for (const f of walk(join(REPO, 'supabase', 'functions'))) {
    if (/(counterpart_model|counterpartModel)\s*:\s*'deterministic'/.test(readFileSync(f, 'utf8')))
      assert.fail(`${relative(REPO, f)} hard-codes a code author for a review`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

const probe = (required) => String.raw`
do $p$
declare
  o jsonb := '[]'::jsonb; r record; a record; m text; v jsonb; routed boolean; authors text[];
  req constant jsonb := '${JSON.stringify(required)}'::jsonb;
  fam text; mf text; ff text; n int := 0; ex jsonb := '{}'::jsonb; viol bigint := null;
begin
  for r in select p.task_class, array(select jsonb_array_elements_text(case when jsonb_typeof(to_jsonb(p)->'reviews_class') = 'array' then to_jsonb(p)->'reviews_class' else '[]'::jsonb end)) reviews_class from public.model_policy p
            where p.task_class in (select jsonb_object_keys(req)) order by 1 loop
    routed := cardinality(coalesce(r.reviews_class, '{}')) > 0;
    authors := case when routed then r.reviews_class else array(select jsonb_array_elements_text(req->r.task_class)) end;
    for a in select p.task_class, p.model_primary, p.model_fallback from public.model_policy p where p.task_class = any (authors) loop
      foreach m in array array_remove(array[a.model_primary, a.model_fallback], null) loop
        continue when m = 'none';
        -- two statements, not one CASE: before the file is applied fn_ai_route_review may not exist, and plpgsql
        -- plans only the branch it runs
        if routed then v := public.fn_ai_route_review(r.task_class, m);
        else v := public.fn_ai_route(r.task_class, null, null, null, false, null, null); end if;
        select lower(btrim(provider)) into fam from public.model_registry where model_id = m;
        n := n + 1;
        mf := (select lower(btrim(provider)) from public.model_registry where model_id = v->>'model');
        ff := (select lower(btrim(provider)) from public.model_registry where model_id = v->>'fallback');
        if not routed then
          o := o || to_jsonb(r.task_class || ' is not a declared review class: routes as configured to ' || coalesce(v->>'model', 'none') || ' over ' || a.task_class || ' on ' || m);
        elsif v->>'model' is null then
          o := o || to_jsonb(r.task_class || ' over ' || a.task_class || ' on ' || m || ': no reviewer of another family');
        end if;
        if mf = fam then o := o || to_jsonb(r.task_class || ' PRIMARY ' || (v->>'model') || ' shares ' || fam || ' with ' || a.task_class || ' on ' || m); end if;
        if ff = fam then o := o || to_jsonb(r.task_class || ' FALLBACK ' || (v->>'fallback') || ' shares ' || fam || ' with ' || a.task_class || ' on ' || m); end if;
        if routed and r.task_class = 'identity_redaction_verify' and v->>'fallback' is null then
          o := o || to_jsonb('identity_redaction_verify over ' || m || ' has no fallback'); end if;
        if routed and r.task_class = 'identity_redaction_verify' then
          ex := ex || jsonb_build_object(m, (v->>'model') || ' then ' || coalesce(v->>'fallback', 'none')); end if;
      end loop;
    end loop;
  end loop;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ai_cost_log' and column_name = 'review_violation') then
    execute 'select count(*) from public.ai_cost_log where review_violation is not null and occurred_at > now() - interval ''30 days''' into viol;
  end if;
  raise exception 'CHK<<%>>', jsonb_build_object('bad', coalesce((select jsonb_agg(x) from (select x from jsonb_array_elements(o) x limit 5) q), '[]'::jsonb), 'bad_count', jsonb_array_length(o), 'pairs', n, 'verify', ex, 'violations_30d', viol,
    'declared', (select count(*) from public.model_policy where task_class in (select jsonb_object_keys(req)))) ::text;
end $p$;`;

test('production, one aborted transaction: no review class can route to any of its authors\' families', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [s] = await sql(`select to_regprocedure('public.fn_ai_route_review(text,text,text,text,text)') is not null base_applied,
    exists (select 1 from information_schema.columns where table_schema='public' and table_name='model_policy' and column_name='reviews_class') applied`, { readOnly: true });
  const noReplay = process.env.XFAM_NO_REPLAY === '1';
  const required = Object.fromEntries(Object.entries(declared()));
  const body = (noReplay ? '' : (s.base_applied ? '' : read(BASE) + '\n') + (s.applied ? '' : read(FILE) + '\n')) + probe(required);
  let out;
  try { await sql(body, { retry: false }); } catch (e) {
    const mm = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!mm) throw e;
    out = JSON.parse(mm[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  // the management API returns only the first ~2,000 characters of an error, so five findings travel with the count
  const bad = [...out.bad];
  if (out.bad_count > bad.length) bad.push(`... and ${out.bad_count - bad.length} more`);
  if (out.violations_30d) bad.push(`${out.violations_30d} logged review call(s) flagged SAME_FAMILY_REVIEW / REVIEW_WITHOUT_COUNTERPART in 30 days`);
  console.log(JSON.stringify({ mode: noReplay ? 'production as it is' : 'with the files replayed', pairs: out.pairs, redaction_verify: out.verify, failures: bad.length }, null, 1));
  if (bad.length) console.log(bad.join('\n'));
  assert.ok(out.pairs >= 20, `too few author pairs evaluated (${out.pairs}): the declaration or the policy is missing`);
  assert.deepEqual(bad, [], 'a review class can route onto its author\'s family');
});
