// a_document_still_being_read_holds_the_supplier_and_reaches_the_sales_engineer — review of #1404, 13 Oct 2026.
// Seat: sales_engineer (the gate and the queue); it_engineer (the check).
//
// A supplier's profile or catalogue is marked 'reading' before it is parsed (supplier_doc_trades.markReading), so an
// edge worker killed at its CPU cap leaves it held. This proves, on production, in ONE transaction that always rolls
// back (safe_replay), on ZZ DEMO rows only (…@example.invalid, no auth user, nothing sent - the rows never commit):
//   1. a complete supplier with a document still 'reading' is held: pending, documents_being_read, logged needs_review;
//   2. the sweep (fn_supplier_doc_reading_escalate) turns a document 'reading' for over 30 minutes into unreadable, files
//      ONE document_read_stuck action for sales_engineer, and re-runs the gate, so the supplier is no longer held for it;
//   3. a second run of the sweep files nothing more (no duplicates);
//   4. a 'reading' document with no read_at and a fresh capability row is NOT escalated on the first run.
// The SQL file is replayed first, so the check measures the committed code before it is applied.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_supplier_document_still_being_read_holds_approval_and_reaches_the_sales_engineer.sql';
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

const body = readFileSync(join(REPO, FILE), 'utf8').replace(/-- Verdict row[\s\S]*$/, '');
const ZZ = 'zz-demo-reading-hold';
const PROBE = String.raw`
insert into storage.objects (bucket_id, name) values ('supplier-docs', 'licenses/${ZZ}/l.pdf'), ('supplier-docs', 'profiles/${ZZ}/p.pdf');
insert into public.leads (approval_status, verified, company_name, email, phone, owner_email_verified, owner_phone_verified, accepted_terms_at,
                          signed_terms_path, license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry, trade_license_no,
                          emirate, city, source, tags)
values (null, false, 'ZZ DEMO reading hold', '${ZZ}@example.invalid', '+971500000918', true, true, now(), 'terms/${ZZ}/t.pdf',
        'licenses/${ZZ}/l.pdf', 'profiles/${ZZ}/p.pdf', 'ZZ DEMO reading hold', '2028-12-31', 'ZZRH-1', 'Dubai', 'Dubai', 'probe', array['qd_demo']);
do $p$
declare lid bigint; g1 jsonb; s1 jsonb; s2 jsonb; st text; n int; act text; rec text; reason_after text; fresh jsonb;
begin
  select id into lid from public.leads where email = '${ZZ}@example.invalid';
  insert into public.supplier_capabilities (supplier_id, source_docs, extracted_at)
  values (lid, jsonb_build_object('docs', jsonb_build_array(jsonb_build_object('path', 'profiles/${ZZ}/p.pdf', 'name', 'p.pdf', 'kind', 'profile',
          'status', 'reading', 'trades', '[]'::jsonb, 'read_at', (now() - interval '45 minutes')::text))), now() - interval '45 minutes');
  g1 := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  select status, recommendation into act, rec from public.agent_actions where kind = 'supplier_verification' and target_id = lid::text order by id desc limit 1;
  s1 := public.fn_supplier_doc_reading_escalate(30, 200);
  select e ->> 'status' into st from public.supplier_capabilities c, jsonb_array_elements(c.source_docs -> 'docs') e where c.supplier_id = lid;
  select licence_gate_reason into reason_after from public.leads where id = lid;
  s2 := public.fn_supplier_doc_reading_escalate(30, 200);
  select count(*) into n from public.agent_actions where kind = 'document_read_stuck' and target_id like lid::text || ':%';
  -- a 'reading' document with no read_at, on a capability row read just now, is not escalated
  update public.supplier_capabilities set extracted_at = now(),
         source_docs = jsonb_build_object('docs', jsonb_build_array(jsonb_build_object('path', 'profiles/${ZZ}/q.pdf', 'name', 'q.pdf', 'kind', 'profile', 'status', 'reading', 'trades', '[]'::jsonb)))
   where supplier_id = lid;
  fresh := public.fn_supplier_doc_reading_escalate(30, 200);
  raise exception 'CHK<<%>>', jsonb_build_object('gate_reason', g1 ->> 'reason', 'gate_decision', g1 ->> 'decision', 'logged', act, 'recommendation', left(rec, 40),
    'swept', (select count(*) from jsonb_array_elements(s1) x where (x ->> 'supplier_id')::bigint = lid), 'status_after', st, 'reason_after', reason_after,
    'second_run', (select count(*) from jsonb_array_elements(s2) x where (x ->> 'supplier_id')::bigint = lid), 'actions', n,
    'fresh_swept', (select count(*) from jsonb_array_elements(fresh) x where (x ->> 'supplier_id')::bigint = lid))::text;
end $p$;`;

test('production, one aborted transaction on ZZ DEMO rows: held while reading, swept once, gate re-run, no duplicates',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  let r = null;
  try { await replaySql(body + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe committed instead of rolling back');
  assert.deepEqual([r.gate_decision, r.gate_reason], ['pending', 'documents_being_read'], JSON.stringify(r));
  assert.equal(r.logged, 'needs_review', 'a held supplier is logged for review, not auto_done');
  assert.match(r.recommendation, /^Held: a company profile or catalogue/);
  assert.equal(r.swept, 1);
  assert.equal(r.status_after, 'unreadable');
  assert.notEqual(r.reason_after, 'documents_being_read', 'the gate was re-run after the sweep');
  assert.equal(r.second_run, 0, 'a second run finds nothing');
  assert.equal(r.actions, 1, 'exactly one action, no duplicate');
  assert.equal(r.fresh_swept, 0, 'a reading document with no read_at on a fresh row is not escalated on the first run');
});
