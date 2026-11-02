// A LICENCE READ BY ITS TRADE NAME IS JUDGED LIKE ANY LICENCE NAME (sales_engineer, review of #1711, 28 Oct 2026).
//
// #1711 lets license_extract take the trade name as the licensed name when a licence prints no other name (a Dubai
// licence whose one name line is "Trade Name"). That name reaches leads.licence_legal_name through licenceNameFromModel,
// and the review, public.fn_sales_engineer_verifies_supplier, judges it. The normaliser half is proved offline by
// supabase/functions/_shared/licence_extract.test.ts. This proves the review half on production, in ONE transaction that
// always rolls back (safe_replay), on ZZ DEMO rows only (…@example.invalid, no auth user; nothing commits, so nothing is
// sent), with automatic approval forced ON inside the transaction - the strongest case:
//   A. a trade name that is ANOTHER claimed supplier's registered name is held (licence_name_mismatch), never approved,
//      and the company keeps the name it entered: one company's identity is never handed to another;
//   B. a trade name that differs from the name the supplier entered becomes the company name (founder ruling 1176,
//      "auto fill the name from the attachment instead of rejection") before any approval: a supplier is approved only
//      under the name his licence prints, never under the name he typed;
//   C. a licence name left unread (what a 'low' or unreadable trade-name read leaves) is held as licence_unreadable,
//      never approved automatically.
//   node --test scripts/checks/a_licence_read_by_its_trade_name_is_judged_like_any_licence_name.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { replaySql } from '../lib/safe_replay.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const ZZ = 'zz-demo-tn1711';
const row = (k, entered, licenceName, n) => `(null, false, true, '${ZZ}-${k}@example.invalid', '${entered}', '${ZZ}-${k}@example.invalid',
  '+9715001711${n}', true, true, now(), 'terms/${ZZ}/${k}.pdf', 'licenses/${ZZ}/${k}.pdf', 'profiles/${ZZ}/${k}.pdf',
  ${licenceName === null ? 'null' : `'${licenceName}'`}, '2028-12-31', 'ZZTN1711-${k.toUpperCase()}', 'Dubai', 'Dubai', 'probe', array['qd_demo'])`;
const PROBE = String.raw`
insert into storage.objects (bucket_id, name)
select 'supplier-docs', d || '/${ZZ}/' || k || '.pdf' from unnest(array['licenses', 'profiles']) d, unnest(array['h', 'a', 'b', 'c']) k;
insert into public.leads (approval_status, verified, claimed, claimed_by, company_name, email, phone, owner_email_verified, owner_phone_verified,
                          accepted_terms_at, signed_terms_path, license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry,
                          trade_license_no, emirate, city, source, tags)
values ${row('h', 'ZZ DEMO TN1711 Holder Trading LLC', 'ZZ DEMO TN1711 Holder Trading LLC', '10')},
       ${row('a', 'ZZ DEMO TN1711 Entered A LLC', 'ZZ DEMO TN1711 Holder Trading LLC', '11')},
       ${row('b', 'ZZ DEMO TN1711 Entered B LLC', 'ZZ DEMO TN1711 Printed B Aluminium LLC', '12')},
       ${row('c', 'ZZ DEMO TN1711 Entered C LLC', null, '13')};
do $p$
declare r jsonb := '{}'::jsonb; k text; lid bigint; g jsonb; l public.leads;
begin
  update public.pricing_config set auto_approve_suppliers = true where id = 1;
  foreach k in array array['a', 'b', 'c'] loop
    select id into lid from public.leads where email = '${ZZ}-' || k || '@example.invalid';
    -- Since ledger 1469 a supplier is approved only once it has confirmed its services; b is the case that reaches the approval,
    -- so it carries a confirmed record (true before and after that gate is applied).
    if k = 'b' then
      insert into public.supplier_capabilities (supplier_id, trades, roles, confirmed_at, confirmed_version, review_status)
      values (lid, array['aluminium'], array['contractor'], now(), 1, 'confirmed');
      insert into public.supplier_capability_confirmation (supplier_id, version, confirmed_at, confirmed_via) values (lid, 1, now(), 'portal');
    end if;
    g := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
    select * into l from public.leads where id = lid;
    r := r || jsonb_build_object(k, jsonb_build_object('decision', g ->> 'decision', 'reason', g ->> 'reason', 'status', l.approval_status,
           'verified', l.verified, 'company', l.company_name, 'demo', l.company_name like 'ZZ DEMO %' and l.email like '%@example.invalid'));
  end loop;
  raise exception 'CHK<<%>>', r::text;
end $p$;`;

test('production, one aborted transaction on ZZ DEMO rows, automatic approval ON: a trade name is judged like any licence name',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  let r = null;
  try { await replaySql(PROBE, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    r = JSON.parse(m[1].replace(/^PROBE OK /, '').replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe committed instead of rolling back');
  for (const k of ['a', 'b', 'c']) assert.equal(r[k].demo, true, `case ${k} is not a ZZ DEMO fixture`);
  // A. another claimed supplier's name: held for a person, never approved, the entered name kept
  assert.deepEqual([r.a.decision, r.a.reason, r.a.verified, r.a.company], ['action_required', 'licence_name_mismatch', false, 'ZZ DEMO TN1711 Entered A LLC'], JSON.stringify(r.a));
  // B. a different trade name becomes the company name before the approval: approved only under the printed name
  assert.equal(r.b.company, 'ZZ DEMO TN1711 Printed B Aluminium LLC', JSON.stringify(r.b));
  assert.deepEqual([r.b.decision, r.b.verified], ['approved', true], JSON.stringify(r.b));
  // C. an unread licence name: held, never approved automatically
  assert.deepEqual([r.c.decision, r.c.reason, r.c.verified, r.c.company], ['pending', 'licence_unreadable', false, 'ZZ DEMO TN1711 Entered C LLC'], JSON.stringify(r.c));
});
