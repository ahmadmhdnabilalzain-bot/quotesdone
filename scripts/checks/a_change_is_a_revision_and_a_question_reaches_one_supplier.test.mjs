// A CHANGE IS A REVISION, AND A QUESTION REACHES ONE SUPPLIER (sales_engineer, CUSTOMER_W2, 16 Nov 2026; holes/CUSTOMER.md
// items 5 and 6). The scenarios are a bank, not rules (scripts/eval/request_revision_and_supplier_question_bank.mjs): what a UAE
// customer writes after his request went out, in English, Arabic and Gulf dialect, and what the sales engineer's reading of it
// must lead to.
//
// What fails if it breaks:
//   offline — the bank drops under 12 scenarios per hole or 4 per language, a scenario loses its reading or expectation, or the
//     SQL stops filing the model's reading (the trigger on a customer note, the question door) or stops applying it.
//   local database (QD_LOCAL_DB_URL, built by scripts/db/local_pg16.mjs; NEVER production) — for every scenario the fixture is
//     written and rolled back, the message is filed, the reading is applied through fn_reason_held_resolve, and the record, the
//     revision, the staled quotes, the notices and the customer's facts are checked, with nothing of the customer reaching a
//     supplier and nothing of the supplier reaching the customer. Without a local database that part is reported NOT RUN.
//   env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=<url> node --test scripts/checks/a_change_is_a_revision_and_a_question_reaches_one_supplier.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { REVISIONS, QUESTIONS, CUSTOMER, SUPPLIERS, REQUEST, QUOTES, NEVER_TO_SUPPLIERS, NEVER_TO_CUSTOMER_BEFORE_REVEAL } from '../eval/request_revision_and_supplier_question_bank.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const REV_SQL = 'scripts/sql/a_change_to_a_sent_request_is_a_revision_every_quote_names_and_every_supplier_is_told.sql';
const Q_SQL = 'scripts/sql/a_customer_asks_one_supplier_about_its_quote_before_paying_and_hears_back.sql';
const LOCAL = process.env.QD_LOCAL_DB_URL || '';

test('the bank holds at least 12 scenarios per hole, in English and Arabic, each with its reading and expectation', () => {
  for (const [name, bank] of [['revisions', REVISIONS], ['questions', QUESTIONS]]) {
    assert.ok(bank.length >= 12, `${name}: ${bank.length}`);
    assert.equal(new Set(bank.map((s) => s.id)).size, bank.length, `${name}: duplicate id`);
    for (const l of ['en', 'ar']) assert.ok(bank.filter((s) => s.lang === l).length >= 4, `${name}: fewer than 4 in ${l}`);
    for (const s of bank) assert.ok(s.msg && s.reading?.choice && s.expect, `${s.id}: incomplete`);
  }
  assert.ok(REVISIONS.some((s) => s.reading.choice === 'addendum_only') && REVISIONS.some((s) => s.expect.revision === 1 && s.reading.choice === 'revise'),
    'the bank must hold a message that changes nothing and a reading code must refuse');
  assert.ok(QUESTIONS.some((s) => s.reading.choice === 'answered_from_quote') && QUESTIONS.some((s) => s.reading.choice === 'relay_to_supplier'));
});

test('the SQL files the model reading and applies it; code never decides what a message means', () => {
  const rev = R(REV_SQL), q = R(Q_SQL);
  assert.match(rev, /create trigger z10_a_customer_note_is_read_for_a_revision after insert on public\.rfq_clarification/);
  assert.match(rev, /'sales_engineer', 'sales_engineer\.request_revision'/);
  assert.match(rev, /function public\.fn_reason_apply_sales_engineer__request_revision\(p_id bigint, p_result jsonb\)/);
  assert.match(q, /'sales_engineer', 'sales_engineer\.customer_question'/);
  assert.match(q, /function public\.fn_reason_apply_sales_engineer__customer_question\(p_id bigint, p_result jsonb\)/);
  // no keyword routing over the customer's words in either reading's apply
  for (const body of [rev.slice(rev.indexOf('fn_reason_apply_sales_engineer__request_revision')), q.slice(q.indexOf('fn_reason_apply_sales_engineer__customer_question'))]) {
    assert.doesNotMatch(body.slice(0, 4000), /question_as_written\s*~\*?\s*'|answer_as_written\s*~\*?\s*'/, 'a regex over his words decides');
  }
});

const lit = (s) => '$q$' + String(s) + '$q$';
const arr = (xs) => 'array[' + xs.map(lit).join(', ') + ']::text[]';
function fixture(lang) {
  return `
  perform set_config('qd.probe_files_demo_handoff', 'on', true);
  insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
  select 'delivery.request', s, 'customer_support', 'probe copy', 'fn_customer_support_acts_on_handoff', null, false, 'scripts/sql/the_it_engineer_closes_every_loop_it_opens.sql'
    from unnest(array['sales_engineer', 'customer_support']) s on conflict (type, from_seat, to_seat) do nothing;
  insert into public.customers (id, full_name, email, phone, phone_verified, email_verified, locale) values (c, ${lit(CUSTOMER.name)}, ${lit(CUSTOMER.email)}, ${lit(CUSTOMER.phone)}, true, true, ${lit(lang)});
  insert into public.leads (company_name, email) values (${lit(SUPPLIERS.A)}, 'zz-demo-revq-sa@example.invalid') returning id into sa;
  insert into public.leads (company_name, email) values (${lit(SUPPLIERS.B)}, 'zz-demo-revq-sb@example.invalid') returning id into sb;
  insert into public.inquiries (id, customer_id, category, emirate, summary, budget, required_by, status, lang, created_at)
  values (i, c, ${lit(REQUEST.category)}, ${lit(REQUEST.emirate)}, ${lit(REQUEST.summary)}, ${lit(REQUEST.budget)}, today + ${REQUEST.required_by_days}, 'quoted', ${lit(lang)}, now() - interval '3 days');
  insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, sent_at, match_reason) select i, s, 0.9, now() - interval '70 hours', 'ZZ DEMO' from unnest(array[sa, sb]) s;
  ${['A', 'B'].map((k) => `
  insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, labour)
  values (q${k}::text, 1, 'ZZ DEMO exterior paint and labour', ${lit(QUOTES[k].brand)}, 'ZX-9', 'two coats', 1, 'lot', ${QUOTES[k].amount}, 5000);
  insert into public.quotes (id, inquiry_id, supplier_id, quote_amount, status, warranty, lead_time, payment_terms, exclusions, scope, validity)
  values (q${k}, i, s${k.toLowerCase()}, ${QUOTES[k].amount}, 'submitted', ${lit(QUOTES[k].warranty)}, ${lit(QUOTES[k].lead_time)}, '50% advance', ${lit(QUOTES[k].exclusions)}, ${lit(QUOTES[k].scope)}, '30 days');`).join('')}
  insert into public.quote_quality_hold (quote_id, inquiry_id, supplier_id, fixture, flags, fixes_en, accepted_md5, held_at, release_due, released_at, release_reason)
  select q.id, q.inquiry_id, q.supplier_id, true, '[]'::jsonb, '', '', now(), now(), now(), 'waited_24h' from public.quotes q where q.id in (qA, qB)
  on conflict (quote_id) do update set released_at = now(), release_reason = 'waited_24h', superseded_at = null;
  update public.quotes set status = 'submitted' where id in (qA, qB);
  perform public.fn_customer_supplier_letters(array[i], jsonb_build_array(jsonb_build_object('inquiry_id', i, 'supplier_id', sa), jsonb_build_object('inquiry_id', i, 'supplier_id', sb)), 'quote_card');`;
}
const DECL = `c uuid := gen_random_uuid(); i uuid := gen_random_uuid(); qA uuid := gen_random_uuid(); qB uuid := gen_random_uuid(); sa bigint; sb bigint;
  today date := (now() at time zone 'Asia/Dubai')::date; f text := ''; h bigint; k bigint; v jsonb; r record; facts text; n int;`;

function revisionSql(s) {
  const fl = s.reading.fields || {};
  const fields = Object.entries(fl).map(([key, val]) => key === 'required_by_days'
    ? `'required_by', jsonb_build_object('value', to_char(today + ${Number(val)}, 'YYYY-MM-DD'))`
    : `${lit(key)}, jsonb_build_object('value', ${lit(val)})`).join(', ');
  const e = s.expect;
  return `do $p$ declare ${DECL} begin ${fixture(s.lang)}
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, answer, answered_at, source) values (i, null, 'note', ${lit(s.msg)}, now(), 'rfq_note') returning id into k;
  if exists (select 1 from public.reasoning_held_question where dedupe_key = 'request_revision:' || k) then f := f || ' [a demo note filed a reasoning question]'; end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('sales_engineer', 'sales_engineer.request_revision', 'ZZ DEMO', '{}'::jsonb, '{}'::jsonb, jsonb_build_object('inquiry_id', i, 'clarification_id', k, 'customer_id', c), 'bank', 'bank_rev:' || k) returning id into h;
  v := public.fn_reason_held_resolve(h, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO', 'decision', jsonb_build_object('choice', ${lit(s.reading.choice)}, 'fields', jsonb_build_object(${fields}))));
  select * into r from public.inquiries where id = i;
  if r.revision <> ${e.revision} then f := f || ' [revision ' || r.revision || ', expected ${e.revision}: ' || v::text || ']'; end if;
  ${e.budget ? `if r.budget is distinct from ${lit(e.budget)} then f := f || ' [budget ' || coalesce(r.budget, 'null') || ']'; end if;` : `if r.budget is distinct from ${lit(REQUEST.budget)} and ${e.revision} = 1 then f := f || ' [budget changed]'; end if;`}
  ${e.emirate ? `if r.emirate is distinct from ${lit(e.emirate)} then f := f || ' [emirate ' || coalesce(r.emirate, 'null') || ']'; end if;` : ''}
  ${e.required_by_days != null ? `if r.required_by is distinct from today + ${e.required_by_days} then f := f || ' [date ' || coalesce(r.required_by::text, 'null') || ']'; end if;` : `if r.required_by is distinct from today + ${REQUEST.required_by_days} then f := f || ' [date changed]'; end if;`}
  ${e.summary_has ? `if position(${lit(e.summary_has)} in coalesce(r.summary, '')) = 0 then f := f || ' [summary ' || coalesce(r.summary, '') || ']'; end if;` : ''}
  select count(*) into n from public.quotes where inquiry_id = i and stale_at is not null and coalesce(priced_revision, 1) = 1;
  if (n > 0) <> ${e.staled ? 'true' : 'false'} then f := f || ' [staled ' || n || ']'; end if;
  ${(e.supplier_told_has || []).map((t) => `if not exists (select 1 from public.notifications where inquiry_id = i and to_role = 'supplier' and position(${lit(t)} in body) > 0) then f := f || ' [no supplier told: ' || ${lit(t)} || ']'; end if;`).join('\n  ')}
  if exists (select 1 from public.notifications x, unnest(${arr(NEVER_TO_SUPPLIERS)}) w where x.inquiry_id = i and x.to_role = 'supplier' and x.type <> 'rfq_addendum_raw' and position(w in coalesce(x.body, '') || coalesce(x.subject, '')) > 0) then f := f || ' [a supplier notice names the customer]'; end if;
  if exists (select 1 from public.notifications where inquiry_id = i and to_role = 'customer' and type = 'inquiry_edit_staled_quotes') <> ${e.customer_told ? 'true' : 'false'} then f := f || ' [customer told: expected ${e.customer_told}]'; end if;
  ${e.customer_told ? `if not exists (select 1 from public.notifications where inquiry_id = i and to_role = 'customer' and lang = ${lit(s.lang)}) then f := f || ' [customer not told in ${s.lang}]'; end if;` : ''}
  if f <> '' then raise exception 'CHK<<FAIL%>>', f; end if; raise exception 'CHK<<OK>>'; end $p$;`;
}

function questionSql(s) {
  const fl = s.reading.fields || {};
  const fields = Object.entries(fl).map(([key, val]) => `${lit(key)}, jsonb_build_object('value', ${lit(val)})`).join(', ');
  const e = s.expect; const sup = s.quote === 'A' ? 'sa' : 'sb'; const other = s.quote === 'A' ? 'sb' : 'sa'; const qq = 'q' + s.quote;
  const arabic = /[؀-ۿ]/.test(s.msg);
  return `do $p$ declare ${DECL} begin ${fixture(s.lang)}
  insert into public.rfq_clarification (inquiry_id, supplier_id, kind, question, question_as_written, asked_by, quote_id, source)
  values (i, ${sup}, 'question', ${arabic ? `'A question from the customer, held for the sales engineer.'` : lit(s.msg)}, ${lit(s.msg)}, 'customer', ${qq}, 'portal') returning id into k;
  if public.fn_sales_engineer_customer_question_file(k) is not null then f := f || ' [a demo question filed a reasoning question]'; end if;
  insert into public.reasoning_held_question (seat, surface, question, request, plan, subject, reason, dedupe_key)
  values ('sales_engineer', 'sales_engineer.customer_question', 'ZZ DEMO', '{}'::jsonb, '{}'::jsonb, jsonb_build_object('inquiry_id', i, 'quote_id', ${qq}, 'clarification_id', k, 'customer_id', c), 'bank', 'bank_cq:' || k) returning id into h;
  v := public.fn_reason_held_resolve(h, jsonb_build_object('status', 'answered', 'answer', 'ZZ DEMO', 'decision', jsonb_build_object('choice', ${lit(s.reading.choice)}, 'fields', jsonb_build_object(${fields}))));
  select * into r from public.rfq_clarification where id = k;
  if r.answered_by is distinct from ${e.answered_by ? lit(e.answered_by) : 'null'} then f := f || ' [answered_by ' || coalesce(r.answered_by, 'null') || ': ' || v::text || ']'; end if;
  if (r.relayed_at is not null) <> ${e.relayed ? 'true' : 'false'} then f := f || ' [relayed: expected ${e.relayed}]'; end if;
  if exists (select 1 from public.notifications where quote_id = ${qq} and to_role = 'customer') <> ${e.customer_told ? 'true' : 'false'} then f := f || ' [customer told: expected ${e.customer_told}]'; end if;
  facts := public.fn_customer_inquiry_facts(c, 10)::text;
  ${(e.facts_has || []).map((t) => `if position(${lit(t)} in facts) = 0 then f := f || ' [facts lack: ' || ${lit(t)} || ']'; end if;`).join('\n  ')}
  ${(e.facts_must_not || []).map((t) => `if position(${lit(t)} in facts) > 0 then f := f || ' [facts carry: ' || ${lit(t)} || ']'; end if;`).join('\n  ')}
  if exists (select 1 from unnest(${arr(NEVER_TO_CUSTOMER_BEFORE_REVEAL)}) w where position(w in facts) > 0) then f := f || ' [the facts name the supplier or its brand]'; end if;
  if exists (select 1 from public.notifications x, unnest(${arr(NEVER_TO_CUSTOMER_BEFORE_REVEAL)}) w where x.inquiry_id = i and x.to_role = 'customer' and position(w in coalesce(x.body, '')) > 0) then f := f || ' [a customer notice names the supplier]'; end if;
  ${(e.supplier_told_has || []).map((t) => `if not exists (select 1 from public.notifications where lead_id = ${sup} and to_role = 'supplier' and position(${lit(t)} in body) > 0) then f := f || ' [supplier not told: ' || ${lit(t)} || ']'; end if;`).join('\n  ')}
  if exists (select 1 from public.notifications where lead_id = ${other} and inquiry_id = i) then f := f || ' [the other supplier was written]'; end if;
  if exists (select 1 from public.notifications x, unnest(${arr(NEVER_TO_SUPPLIERS)}) w where x.inquiry_id = i and x.to_role = 'supplier' and position(w in coalesce(x.body, '') || coalesce(x.subject, '')) > 0) then f := f || ' [a supplier notice names the customer]'; end if;
  ${e.seat_queue ? `if not exists (select 1 from public.agent_actions where kind = 'customer_question_waiting' and target_id = k::text) then f := f || ' [not in the sales engineer queue]'; end if;` : ''}
  if f <> '' then raise exception 'CHK<<FAIL%>>', f; end if; raise exception 'CHK<<OK>>'; end $p$;`;
}

function runLocal(sql) {
  const r = spawnSync('psql', ['-X', '-q', LOCAL, '-c', sql], { encoding: 'utf8', maxBuffer: 16 << 20 });
  const m = /CHK<<(.*?)>>/s.exec(String(r.stderr) + String(r.stdout));
  return m ? m[1] : 'NO VERDICT: ' + String(r.stderr).slice(0, 400);
}

test('LOCAL: every revision scenario lands in the record, the quotes and the notices', { skip: LOCAL ? false : 'NOT RUN: no QD_LOCAL_DB_URL (never production)' }, () => {
  const bad = REVISIONS.map((s) => [s.id, runLocal(revisionSql(s))]).filter(([, v]) => v !== 'OK');
  assert.deepEqual(bad, []);
});

test('LOCAL: every question scenario reaches only its supplier, or the customer from the quote, and his facts', { skip: LOCAL ? false : 'NOT RUN: no QD_LOCAL_DB_URL (never production)' }, () => {
  const bad = QUESTIONS.map((s) => [s.id, runLocal(questionSql(s))]).filter(([, v]) => v !== 'OK');
  assert.deepEqual(bad, []);
});
