// a_trade_read_off_a_picture_waits_for_the_sales_engineer — review of #1412, 18 Oct 2026.
// Seat: sales_engineer (the decision); it_engineer (the check).
//
// Trades read off a picture are held (source_docs.docs[].vision_held) with one pending vision_trades_confirm item.
// This proves, on production, in ONE transaction that always rolls back (safe_replay), on ZZ DEMO rows only:
//   1. a second pending item for the same supplier and document is refused by the table (unique_violation);
//   2. confirming one of two held codes moves only that code into the document's trades and proposed_trades, clears
//      vision_held and closes the item 'done'; deciding it again is refused;
//   3. rejecting (nothing confirmed) proposes nothing, clears vision_held and closes the item 'dismissed'.
// The SQL file is replayed first, so the check measures the committed code before it is applied.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/a_trade_read_off_a_picture_waits_for_the_sales_engineer_to_confirm_it.sql';
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const body = readFileSync(join(REPO, FILE), 'utf8');
const ZZ = 'zz-demo-vision-held';
const PROBE = String.raw`
insert into public.leads (company_name, email, source, tags) values ('ZZ DEMO vision held', '${ZZ}@example.invalid', 'probe', array['qd_demo']);
do $p$
declare lid bigint; a1 bigint; a2 bigint; dup text := 'none'; c1 jsonb; c2 jsonb; r1 jsonb; st1 text; st2 text; tr jsonb; held1 jsonb; held2 jsonb; prop text[];
  held jsonb := jsonb_build_array(jsonb_build_object('code', 'aluminium', 'via', 'model_choice', 'snippet', 'Aluminium works'),
                                  jsonb_build_object('code', 'joinery', 'via', 'model_choice', 'snippet', 'kitchen cabinets'));
begin
  select id into lid from public.leads where email = '${ZZ}@example.invalid';
  insert into public.supplier_capabilities (supplier_id, proposed_trades, source_docs, extracted_at)
  values (lid, '{}', jsonb_build_object('docs', jsonb_build_array(
            jsonb_build_object('path', 'profiles/${ZZ}/a.pdf', 'name', 'a.pdf', 'kind', 'profile', 'status', 'read', 'trades', '[]'::jsonb, 'vision_held', held),
            jsonb_build_object('path', 'profiles/${ZZ}/b.pdf', 'name', 'b.pdf', 'kind', 'profile', 'status', 'read', 'trades', '[]'::jsonb, 'vision_held', held))), now());
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'vision_trades_confirm', 'pending', 'low', 'ZZ DEMO a', jsonb_build_object('supplier_id', lid, 'path', 'profiles/${ZZ}/a.pdf'),
          'supplier_capabilities', lid || ':profiles/${ZZ}/a.pdf') returning id into a1;
  begin
    insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
    values ('sales_engineer', 'vision_trades_confirm', 'pending', 'low', 'ZZ DEMO a again', '{}'::jsonb, 'supplier_capabilities', lid || ':profiles/${ZZ}/a.pdf');
  exception when unique_violation then dup := 'refused';
  end;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'vision_trades_confirm', 'pending', 'low', 'ZZ DEMO b', jsonb_build_object('supplier_id', lid, 'path', 'profiles/${ZZ}/b.pdf'),
          'supplier_capabilities', lid || ':profiles/${ZZ}/b.pdf') returning id into a2;
  c1 := public.fn_sales_engineer_decides_vision_trades(a1, array['aluminium', 'steel']);
  r1 := public.fn_sales_engineer_decides_vision_trades(a1, array['joinery']);
  c2 := public.fn_sales_engineer_decides_vision_trades(a2, '{}');
  select status into st1 from public.agent_actions where id = a1;
  select status into st2 from public.agent_actions where id = a2;
  select proposed_trades into prop from public.supplier_capabilities where supplier_id = lid;
  select e -> 'trades', e -> 'vision_held' into tr, held1 from public.supplier_capabilities c, jsonb_array_elements(c.source_docs -> 'docs') e
   where c.supplier_id = lid and e ->> 'path' like '%/a.pdf';
  select e -> 'vision_held' into held2 from public.supplier_capabilities c, jsonb_array_elements(c.source_docs -> 'docs') e
   where c.supplier_id = lid and e ->> 'path' like '%/b.pdf';
  raise exception 'CHK<<%>>', jsonb_build_object('dup', dup, 'c1', c1 -> 'confirmed', 'again', r1 ->> 'error', 'st1', st1, 'st2', st2,
    'prop', to_jsonb(prop), 'trades_a', (select jsonb_agg(x ->> 'code' || '/' || (x ->> 'via')) from jsonb_array_elements(tr) x),
    'held_a', held1, 'held_b', held2)::text;
end $p$;`;

test('production, one aborted transaction on ZZ DEMO rows: one pending item per document; confirm moves only confirmed codes; reject proposes nothing',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  let r = null;
  try { await replaySql(body + '\n' + PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe committed instead of rolling back');
  assert.equal(r.dup, 'refused', 'a second pending item for the same document is refused by the table');
  assert.deepEqual(r.c1, ['aluminium'], 'only a code that was held is confirmed (steel was never held)');
  assert.equal(r.again, 'already_decided');
  assert.deepEqual([r.st1, r.st2], ['done', 'dismissed']);
  assert.deepEqual(r.prop, ['aluminium'], 'the rejected document proposes nothing');
  assert.deepEqual(r.trades_a, ['aluminium/sales_engineer_confirmed']);
  assert.equal(r.held_a, null); assert.equal(r.held_b, null);
});
