// whatsapp_goes_to_a_confirmed_number.mjs — WhatsApp reaches only a number the person confirmed.
// node scripts/checks/whatsapp_goes_to_a_confirmed_number.mjs          (reads production; needs a Supabase token)
//
// Founder, 14 Sep 2026 (founder_instruction #322): "what if the customer has whatsapp on another phone
// number, maybe we should confirm this point through the sign up".
//
// ONE ABORTED TRANSACTION. ZZ DEMO customers and suppliers at @example.invalid are created in each
// WhatsApp state, notices are queued for them, inbound numbers are resolved, and the result is raised
// out so the transaction rolls back: nothing survives, and every row is captured by the demo guards.
// It proves, for customers AND suppliers:
//   1. 'same'  -> the WhatsApp twin goes to the verified mobile;
//   2. 'other' verified -> to whatsapp_phone, never the mobile;
//   3. 'none'  -> the twin is recorded 'skipped' with the reason, and the email still goes;
//   4. unanswered -> no twin at all; and a row a writer addresses to any number is skipped, not sent;
//   5. a number that is not verified cannot be stored (the table refuses it);
//   6. inbound: a verified 'other' number and a verified 'same' mobile name their owner; an unverified
//      mobile, a scraped leads.whatsapp and a number two parties share name nobody;
//   7. an undelivered email is retried on WhatsApp for a confirmed number, else SMS on the verified
//      mobile (fn_originator_checks_delivery's channel choice, read from the resolvers it calls).
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const REF = 'htdblwldjkcgjvmqkbeh';
const tp = join(homedir(), '.supabase', 'access-token');
const TOKEN = (process.env.SUPABASE_ACCESS_TOKEN || (existsSync(tp) ? readFileSync(tp, 'utf8') : '')).trim();
if (!TOKEN) { console.error('no Supabase token: this check reads production and cannot be skipped'); process.exit(1); }

const WALK = String.raw`
do $walk$
declare
  tag text := substr(md5(random()::text), 1, 8);
  m_same text := '+97150000' || '0081'; m_other text := '+97150000' || '0082'; wa_other text := '+97150000' || '0083';
  m_none text := '+97150000' || '0084'; m_unans text := '+97150000' || '0085'; m_unver text := '+97150000' || '0086';
  scraped text := '+97150000' || '0087'; shared text := '+97150000' || '0088';
  c_same uuid; c_other uuid; c_none uuid; c_unans uuid; c_unver uuid; c_sh1 uuid; c_sh2 uuid; l_same bigint; l_none bigint; l_scraped bigint;
  e text; out jsonb := '{}'::jsonb; refused boolean := false;
  twin record;
begin
  e := '-' || tag || '@example.invalid';
  insert into public.customers (email, full_name, phone, phone_verified, whatsapp_opt) values ('zz-demo-wa-same' || e, 'ZZ DEMO WA Same', m_same, true, 'same') returning id into c_same;
  insert into public.customers (email, full_name, phone, phone_verified, whatsapp_opt, whatsapp_phone, whatsapp_verified_at) values ('zz-demo-wa-other' || e, 'ZZ DEMO WA Other', m_other, true, 'other', wa_other, now()) returning id into c_other;
  insert into public.customers (email, full_name, phone, phone_verified, whatsapp_opt) values ('zz-demo-wa-none' || e, 'ZZ DEMO WA None', m_none, true, 'none') returning id into c_none;
  insert into public.customers (email, full_name, phone, phone_verified) values ('zz-demo-wa-unans' || e, 'ZZ DEMO WA Unanswered', m_unans, true) returning id into c_unans;
  insert into public.customers (email, full_name, phone, phone_verified, whatsapp_opt) values ('zz-demo-wa-unver' || e, 'ZZ DEMO WA Unverified', m_unver, false, 'same') returning id into c_unver;
  insert into public.customers (email, full_name, phone, phone_verified, whatsapp_opt) values ('zz-demo-wa-sh1' || e, 'ZZ DEMO WA Shared 1', shared, true, 'same') returning id into c_sh1;
  insert into public.customers (email, full_name, phone, phone_verified, whatsapp_opt) values ('zz-demo-wa-sh2' || e, 'ZZ DEMO WA Shared 2', shared, true, 'same') returning id into c_sh2;
  insert into public.leads (company_name, email, claimed_by, phone, owner_phone_verified, whatsapp_opt) values ('ZZ DEMO WA Supplier Same', 'zz-demo-wa-ssame' || e, 'zz-demo-wa-ssame' || e, m_same || '9', true, 'same') returning id into l_same;
  insert into public.leads (company_name, email, claimed_by, phone, owner_phone_verified, whatsapp_opt) values ('ZZ DEMO WA Supplier None', 'zz-demo-wa-snone' || e, 'zz-demo-wa-snone' || e, m_none || '9', true, 'none') returning id into l_none;
  insert into public.leads (company_name, email, whatsapp) values ('ZZ DEMO WA Scraped', 'zz-demo-wa-scraped' || e, scraped) returning id into l_scraped;

  -- 5. an unverified number cannot be stored
  begin
    insert into public.customers (email, full_name, whatsapp_opt, whatsapp_phone) values ('zz-demo-wa-bad' || e, 'ZZ DEMO WA Bad', 'other', '+971500000089');
  exception when check_violation then refused := true;
  end;
  out := out || jsonb_build_object('unverified_number_refused', refused);

  -- 1-4. email notices, and the WhatsApp twins they make
  insert into public.notifications (type, to_email, to_role, channel, subject, body) values
    ('new_quote', 'zz-demo-wa-same' || e, 'customer', 'email', 'x', 'x'), ('new_quote', 'zz-demo-wa-other' || e, 'customer', 'email', 'x', 'x'),
    ('new_quote', 'zz-demo-wa-none' || e, 'customer', 'email', 'x', 'x'), ('new_quote', 'zz-demo-wa-unans' || e, 'customer', 'email', 'x', 'x'),
    ('new_quote', 'zz-demo-wa-unver' || e, 'customer', 'email', 'x', 'x');
  insert into public.notifications (type, to_email, to_role, lead_id, channel, subject, body) values
    ('new_inquiry', 'zz-demo-wa-ssame' || e, 'supplier', l_same, 'email', 'x', 'x'), ('new_inquiry', 'zz-demo-wa-snone' || e, 'supplier', l_none, 'email', 'x', 'x');
  -- a writer that addresses WhatsApp itself, to a number of its choosing
  insert into public.notifications (type, to_email, to_role, to_phone, channel, subject, body) values
    ('direct', 'zz-demo-wa-unans' || e, 'customer', m_unans, 'whatsapp', 'x', 'x'),
    ('direct', 'zz-demo-wa-other' || e, 'customer', m_other, 'whatsapp', 'x', 'x');
  insert into public.notifications (type, to_email, to_role, lead_id, to_phone, channel, subject, body) values
    ('direct', 'zz-demo-wa-scraped' || e, 'supplier', l_scraped, scraped, 'whatsapp', 'x', 'x');

  out := out || jsonb_build_object('rows', (select coalesce(jsonb_agg(jsonb_build_object('who', split_part(split_part(n.to_email, '@', 1), '-', 4), 'type', n.type,
           'channel', n.channel, 'to_phone', n.to_phone, 'status', n.status, 'why', n.last_error) order by n.id), '[]'::jsonb)
    from public.notifications n where n.to_email like 'zz-demo-wa-%' || e));

  -- 6. inbound
  out := out || jsonb_build_object('owner', jsonb_build_object(
    'other_wa',  (select jsonb_agg(o) from public.fn_whatsapp_owner(wa_other) o),
    'other_mobile_not_wa', (select jsonb_agg(o) from public.fn_whatsapp_owner(m_other) o),
    'same_mobile', (select jsonb_agg(o) from public.fn_whatsapp_owner(m_same) o),
    'unverified', (select jsonb_agg(o) from public.fn_whatsapp_owner(m_unver) o),
    'scraped', (select jsonb_agg(o) from public.fn_whatsapp_owner(scraped) o),
    'shared', (select jsonb_agg(o) from public.fn_whatsapp_owner(shared) o),
    'identify_scraped', public.fn_identify_contact(scraped)::jsonb,
    'lead_id_scraped', public.fn_wa_lead_id(scraped),
    'lead_id_same', public.fn_wa_lead_id(m_same || '9')));
  out := out || jsonb_build_object('ids', jsonb_build_object('c_same', c_same, 'c_other', c_other, 'l_same', l_same));

  -- 7. the retry channel fn_originator_checks_delivery picks
  out := out || jsonb_build_object('retry', jsonb_build_object(
    'other', public.fn_whatsapp_destination('customer', c_other), 'none_wa', public.fn_whatsapp_destination('customer', c_none),
    'none_sms', public.fn_verified_mobile('customer', c_none), 'unver_sms', public.fn_verified_mobile('customer', c_unver)));

  raise exception 'CHK<<%>>', out;
end $walk$;`;

const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, { method: 'POST', headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ query: WALK }) });
const text = await r.text(); let msg = text; try { const j = JSON.parse(text); msg = String(j.message || text); } catch (_e) { /* raw */ }
const m = msg.match(/CHK<<(.*)>>/s);
if (!m) { console.error('the walk did not report (HTTP ' + r.status + '): ' + msg.slice(0, 500)); process.exit(1); }
const out = JSON.parse(m[1]);
const fails = [];
const ok = (c, s) => { if (!c) fails.push(s); console.log(`  ${c ? 'ok ' : 'BAD'} ${s}`); };
const twin = (who, type = null) => out.rows.filter((x) => x.who === who && x.channel === 'whatsapp' && (!type || x.type === type));
const email = (who) => out.rows.filter((x) => x.who === who && x.channel === 'email');

ok(out.unverified_number_refused, '5. a WhatsApp number without its verification time is refused by the table');
ok(twin('same', 'new_quote').length === 1 && twin('same', 'new_quote')[0].to_phone === '+971500000081', "1. customer 'same': twin to the verified mobile");
ok(twin('ssame').length === 1 && twin('ssame')[0].to_phone === '+9715000000819', "1. supplier 'same': twin to the verified mobile");
ok(twin('other', 'new_quote').length === 1 && twin('other', 'new_quote')[0].to_phone === '+971500000083', "2. 'other': twin to the verified WhatsApp number, not the mobile");
ok(twin('other', 'direct')[0]?.to_phone === '+971500000083', "2. a writer's own number is replaced by the confirmed one");
for (const who of ['none', 'snone']) {
  const t = twin(who);
  ok(t.length === 1 && t[0].status === 'skipped' && /do not use WhatsApp/.test(t[0].why || ''), `3. ${who}: twin recorded skipped with the reason`);
  ok(email(who).length === 1, `3. ${who}: the email still goes`);
}
ok(twin('unans', 'new_quote').length === 0, '4. unanswered: no twin');
ok(twin('unans', 'direct')[0]?.status === 'skipped' && /no confirmed WhatsApp number/.test(twin('unans', 'direct')[0]?.why || ''), '4. a direct WhatsApp to an unanswered customer is skipped');
ok(twin('unver', 'new_quote').length === 0, "4. 'same' with an unverified mobile: no twin");
ok(twin('scraped')[0]?.status === 'skipped', '4. a scraped supplier number is never a route');
const O = out.owner;
ok(O.other_wa?.length === 1 && O.other_wa[0].customer_id === out.ids.c_other, "6. a verified 'other' number names its customer");
ok(!O.other_mobile_not_wa, "6. the mobile of an 'other' customer is not their WhatsApp");
ok(O.same_mobile?.length === 1 && O.same_mobile[0].customer_id === out.ids.c_same, "6. a verified 'same' mobile names its customer");
ok(!O.unverified, '6. an unverified mobile names nobody');
ok(!O.scraped && O.identify_scraped?.audience === 'unknown' && O.lead_id_scraped === null, '6. a scraped listing number names nobody (fn_whatsapp_owner, fn_identify_contact, fn_wa_lead_id)');
ok(!O.shared, '6. a number two customers share names nobody');
ok(Number(O.lead_id_same) === Number(out.ids.l_same), "6. fn_wa_lead_id finds a supplier by a verified 'same' mobile");
const R = out.retry;
ok(R.other === '+971500000083' && R.none_wa === null && R.none_sms === '+971500000084' && R.unver_sms === null, '7. retry: confirmed WhatsApp, else SMS on the verified mobile, never an unverified number');

if (fails.length) { console.error(`\nwhatsapp_goes_to_a_confirmed_number: ${fails.length} failure(s)`); process.exit(1); }
console.log('\nwhatsapp_goes_to_a_confirmed_number: WhatsApp reaches only a confirmed number');
