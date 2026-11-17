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
//     * the redaction verify has no fallback over an OpenAI author (matrix v3, #1479: an Anthropic author has one reviewer);
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
import { replaySql } from '../lib/safe_replay.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/every_review_class_is_judged_by_another_family_than_its_author.sql';
const BASE = 'scripts/sql/a_seat_is_never_reviewed_by_a_model_of_its_own_family.sql';
const FOLLOW = 'scripts/sql/a_review_is_held_rather_than_skipped_and_its_authors_are_the_rows_it_judges.sql';
// The founder's model matrix (founder_instruction 1056): every review class's pair, the pool, and the router trying a
// class's own fallback before the pool. Replayed after FOLLOW when it is not applied yet.
const MATRIX = 'scripts/sql/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql';
// Matrix v2 (5 Oct 2026): replayed while its pending note exists.
const V2 = 'every_seat_runs_luna_with_gemini_behind_and_the_two_retired_models_leave_routing';
const V2_REPLAY = existsSync(join(REPO, 'scripts/sql/pending', `${V2}.txt`)) ? read(`scripts/sql/${V2}.sql`) + '\n' : '';
const MATRIX_APPLIED =`exists (select 1 from public.model_policy where task_class = 'internal_judgement') matrix_applied`;

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
  // The route the redaction verify takes is matrix v2's (5 Oct 2026): the find is read on luna, so the verify runs on
  // Gemini with Opus as the third family behind it.
  const v2 = read(`scripts/sql/${V2}.sql`);
  assert.match(v2, /set model_primary = 'google\/gemini-3\.8-flash', model_fallback = 'anthropic\/claude-opus-5\.5',[\s\S]{0,900}'identity_redaction_verify'/,
    'the redaction verify runs on Gemini with a third-family fallback (Opus)');
});

test('the gateway refuses a review class without its author, and writes the author where the backstop reads it', () => {
  const gw = functionSource('ai_gateway');
  assert.match(gw, /from\('model_policy'\)\.select\('reviews_class'\)/);
  assert.match(gw, /outcome: 'review_needs_counterpart'/);
  assert.match(gw, /route\.why = String\(route\.why \?\? ''\) \+ ' \| counterpart_model=' \+/);
  assert.match(gw, /counterpart \? 0 : Number\(body\.cache_ttl_min/, 'a review is never served from cache');
  // never unreviewed: no independent reviewer => HELD and recorded; a third-family review is tagged
  // (an unknown author is a data-defect finding, not a hold; a failed or unreachable reviewer is a hold too)
  assert.match(gw, /if \(counterpart && route\.no_independent_reviewer && !route\.unknown_author\) \{\s*await rpcSafe\('fn_review_hold_record'/);
  assert.match(gw, /if \(!outMsg && counterpart\) \{[\s\S]{0,200}fn_review_hold_record/, 'a failed reviewer call is held and recorded');
  assert.match(gw, /if \(counterpart && !ladder\.length && fullLadder\.length && skipped\.some/, 'an unreachable reviewer is held and recorded');
  assert.match(gw, /p_require_caps: caps\.length \? caps : null,\s*\}\) : await admin\.rpc\('fn_ai_route'/, 'a review carries its capabilities');
  assert.match(gw, /' \| reviewer_tier=' \+ route\.reviewer_tier/);
  assert.match(functionSource('resilience_ping'), /rpc\('fn_it_review_independence_watch'\)/);
  const sql = read(FILE);
  assert.match(sql, /'third_family_fallback'/);
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
      // A review fn's label on a call that names its OWN class is routed by that class (fn_ai_route takes a caller-supplied class
      // before fn_task_class): 16 Nov 2026, ceo_agent's weekly and daily plan calls (ceo_strategic_planning /
      // routine_employee_reasoning) are not reviews. A review class named on such a call is still caught by the class pattern above.
      if (/^fn\s*:/.test(h[0])) {
        const obj = src.slice(h.index, src.indexOf('}', h.index) + 1);
        if (/\btaskClass\b|\btask_class\s*:/.test(obj)) continue;
      }
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
            -- the required classes, AND every live review class (a seat's own review row, founder_instruction 1056)
            where p.task_class in (select jsonb_object_keys(req))
               or (p.active and jsonb_typeof(to_jsonb(p)->'reviews_class') = 'array' and jsonb_array_length(to_jsonb(p)->'reviews_class') > 0)
            order by 1 loop
    routed := cardinality(coalesce(r.reviews_class, '{}')) > 0;
    authors := case when routed then r.reviews_class else array(select jsonb_array_elements_text(req->r.task_class)) end;
    -- every route an author class runs on: its own row, every seat's own row for it ('<seat>__<class>'), and - where
    -- the row has a fallback - every seat's plan B, which replaces the class's fallback for that seat's calls
    for a in select p.task_class, p.model_primary,
                    array_remove(array[p.model_fallback], null)
                    || case when p.model_fallback is null or to_regclass('public.model_policy_by_identity') is null then '{}'::text[]
                            else array(select distinct i.fallback_model from public.model_policy_by_identity i
                                        where i.scope = 'current_agent' and i.fallback_model is not null) end fallbacks
               from public.model_policy p
              where p.task_class = any (authors)
                 or exists (select 1 from unnest(authors) x where right(p.task_class, length(x) + 2) = '__' || x) loop
      foreach m in array array(select distinct y from unnest(array[a.model_primary] || a.fallbacks) y where y is not null) loop
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
        -- matrix v3 (#1479; ruling 1241 Gemini only hears, 1240 Sol removed): two judgement families remain, so an author on
        -- Anthropic has ONE reviewer (Luna Pro) and no fallback by design; the verify must keep a fallback only where
        -- its author writes on OpenAI (the same rule every_seat_runs_the_founders_model_matrix_probe.sql asserts).
        if routed and r.task_class = 'identity_redaction_verify' and v->>'fallback' is null and fam = 'openai' then
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
    exists (select 1 from information_schema.columns where table_schema='public' and table_name='model_policy' and column_name='reviews_class') applied,
    to_regprocedure('public.fn_ai_route_review_for(text,text,text,text,text,text[])') is not null follow_applied,
    ${MATRIX_APPLIED}`, { readOnly: true });
  const noReplay = process.env.XFAM_NO_REPLAY === '1';
  const required = Object.fromEntries(Object.entries(declared()));
  const body = (noReplay ? '' : (s.base_applied ? '' : read(BASE) + '\n') + (s.applied ? '' : read(FILE) + '\n') + (s.follow_applied ? '' : read(FOLLOW) + '\n')
    + (s.matrix_applied ? '' : read(MATRIX) + '\n') + V2_REPLAY) + probe(required);
  let out;
  try { await replaySql(body, { retry: false }); } catch (e) {
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

// #880 REVIEW FOLLOW-UPS (a_review_is_held_rather_than_skipped_and_its_authors_are_the_rows_it_judges.sql), one aborted transaction.
const FOLLOW_PROBE = String.raw`
do $p$
declare o jsonb := '{}'; v jsonb; h bigint; w jsonb;
begin
  -- 1 a hold does not close on the gateway's own refusal row (model 'none', ok true)
  h := public.fn_review_hold_record('ceo_judgement', 'zz_probe_fn', 'ceo', ' openai/gpt-5.6-sol , anthropic/claude-opus-5.5,openai/gpt-5.6-sol', 'ZZ probe');
  o := o || jsonb_build_object('hold_counterpart', (select counterpart_model from public.review_hold where id = h));
  update public.review_hold set last_held_at = now() - interval '1 minute' where id = h;
  insert into public.ai_cost_log (fn, task_class, model_used, model_selected_because, ok)
  values ('zz_probe_fn', 'ceo_judgement', 'none', 'NO INDEPENDENT REVIEWER | counterpart_model=anthropic/claude-opus-5.5,openai/gpt-5.6-sol', true);
  w := public.fn_it_review_independence_watch();
  o := o || jsonb_build_object('open_after_refusal_row', (select closed_at is null from public.review_hold where id = h));
  -- ... and does close on a real independent review after it
  insert into public.ai_cost_log (fn, task_class, model_used, model_selected_because, ok)
  values ('zz_probe_fn', 'ceo_judgement', 'google/gemini-3.8-flash', 'x | counterpart_model=anthropic/claude-opus-5.5,openai/gpt-5.6-sol | reviewer_tier=third_family_fallback', true);
  w := public.fn_it_review_independence_watch();
  o := o || jsonb_build_object('closed_after_real_review', (select closed_at is not null from public.review_hold where id = h));
  -- 3 an unknown author is a data defect, not a hold
  v := public.fn_ai_route_review('quote_comparison', 'unknown,openai/gpt-5.6-sol');
  o := o || jsonb_build_object('unknown_flag', v->>'unknown_author', 'unknown_why', left(v->>'why', 15));
  insert into public.ai_cost_log (fn, task_class, model_used, model_selected_because, ok)
  values ('zz_probe_cmp', 'quote_comparison', 'none', (v->>'why') || ' | counterpart_model=openai/gpt-5.6-sol,unknown', true);
  o := o || jsonb_build_object('unknown_item', (select x->>'owner_seat' from jsonb_array_elements(public.fn_it_review_independence_items()) x
                                                  where x->>'item' = 'review_author_unknown:zz_probe_cmp'));
  -- 5 no last-resort family left, and 7 capabilities. Matrix v2 (5 Oct 2026) retired the fourth last-resort family, so
  -- with Gemini and luna tripped an author on Sol and Opus has no reviewer outside its families: the review is HELD.
  perform set_config('app.change_reason', 'probe:no_review_class_can_route_to_its_authors_family', true);  -- the founder-hold guard admits an aborted probe by name
  update public.llm_route_health set opened_class = 'provider_error', open_until = now() + interval '1 hour'
   where model_id in ('google/gemini-3.8-flash', 'openai/gpt-6-luna');
  -- 10 Nov 2026 (it_engineer): founder ruling 1571 ("pick the right model per task yourself") put Qwen 3.8 Flash in the
  -- active review_pool at rank 4 (simple_tasks_leave_sonnet_and_every_reply_runs_on_the_model_its_task_needs.sql,
  -- MANIFEST 2259), so an author on Sol and Opus has a fourth family again and its review lands there. Proved first;
  -- then Qwen is tripped too, and with no family left outside the authors' the review must still be HELD.
  o := o || jsonb_build_object(
    'text_review_fourth_family', public.fn_ai_route_review('ceo_judgement', 'openai/gpt-5.6-sol,anthropic/claude-opus-5.5')->>'reviewer_family');
  update public.llm_route_health set opened_class = 'provider_error', open_until = now() + interval '1 hour'
   where model_id like 'qwen/%';
  o := o || jsonb_build_object(
    'text_review_held', coalesce(public.fn_ai_route_review('ceo_judgement', 'openai/gpt-5.6-sol,anthropic/claude-opus-5.5')->>'model', 'held'),
    'vision_review', coalesce(public.fn_ai_route_review_for('identity_redaction_verify', 'openai/gpt-5.6-sol,anthropic/claude-opus-5.5',
                                null, null, null, array['vision'])->>'model', 'held'));
  -- 'ceo_authors' (fn_ceo_judgement_counterparts) was read here; the routine was dropped 16 Nov 2026 with the unsent daily
  -- judgement (the_ceos_unsent_daily_judgement_request_is_retired.sql).
  raise exception 'CHK<<%>>', o::text;
end $p$;`;

test('production, one aborted transaction: #880 review follow-ups hold', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [s] = await sql(`select to_regprocedure('public.fn_ai_route_review_for(text,text,text,text,text,text[])') is not null follow_applied,
    ${MATRIX_APPLIED}`, { readOnly: true });
  let out;
  try { await replaySql((s.follow_applied ? '' : read(FOLLOW) + '\n') + (s.matrix_applied ? '' : read(MATRIX) + '\n') + V2_REPLAY + FOLLOW_PROBE, { retry: false }); } catch (e) {
    const mm = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!mm) throw e;
    out = JSON.parse(mm[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  console.log(JSON.stringify(out));
  assert.equal(out.hold_counterpart, 'anthropic/claude-opus-5.5,openai/gpt-5.6-sol', 'one set of authors is one normalised string');
  assert.equal(out.open_after_refusal_row, true, 'the gateway\'s own refusal row must not close a hold');
  assert.equal(out.closed_after_real_review, true, 'a real independent review closes the hold');
  assert.equal(out.unknown_flag, 'true');
  assert.equal(out.unknown_why, 'AUTHOR UNKNOWN:');
  assert.equal(out.unknown_item, 'it_engineer', 'an unknown author is an it_engineer data-defect finding');
  assert.equal(out.text_review_fourth_family, 'qwen', 'ruling 1571: with Gemini and luna down, a Sol+Opus author is reviewed by Qwen');
  assert.equal(out.text_review_held, 'held', 'no retired model is a last-resort family: with every other family down the review is held');
  assert.equal(out.vision_review, 'held', 'a vision review never lands on a text-only reviewer');
});
