// THE SUPPLIER WHATSAPP INVITATION WAITS FOR AN OPT-IN, BOTH SWITCHES AND A HIGH-QUALITY SENDER (marketing, 27 Oct 2026).
// Rulings 1184 (safe channels, nothing that risks bans), 1301 (no link), 1312 (campaign paused). Fails if:
//   - the stored WhatsApp text and the template send_whatsapp / wa_template_setup use differ, carry a link, or lose
//     the STOP line (offline);
//   - anything queues while either switch is off, the brake is open, the sender is not HIGH / ONLINE, outside the
//     Dubai weekday window, or for a lead with no opt-in; or a lead / number is invited twice (production replay,
//     rolled back, DEMO LEADS ONLY: p_demo_only = true selects nothing but ZZ DEMO / example.invalid rows);
//   - a LOW quality reading does not brake and cancel what is queued;
//   - an opt-in is recorded from anything but the "Set up my page" button or a yes to the consent question (founder
//     ledger 1341): "who is this?" never opts in, the button does, a yes (English or Arabic) to the consent question
//     does, a yes to anything else does not, and a direct insert that bypasses the writers is refused.
//   node --test scripts/checks/the_supplier_whatsapp_invitation_waits_for_opt_in_and_both_switches.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = new URL('../../', import.meta.url);
const read = (p) => readFileSync(new URL(p, ROOT), 'utf8');
const FILE = 'scripts/sql/the_supplier_whatsapp_invitation_waits_for_opt_in_both_switches_and_a_high_quality_sender.sql';
const sqlText = read(FILE);
const gateTs = read('supabase/functions/_shared/marketing_send_gate.ts');
const SKIP = (process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'))) ? false : 'no Supabase management token in this environment';

// The TS template, rebuilt from its string concatenation.
function tsTemplate() {
  const m = /export const WA_INVITE_TEMPLATE_EN =\s*([\s\S]*?);\n/.exec(gateTs);
  assert.ok(m, 'WA_INVITE_TEMPLATE_EN not found');
  return [...m[1].matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((x) => x[1].replace(/\\'/g, "'")).join('');
}
const sqlTemplate = () => /c_text constant text := '((?:[^']|'')*)';/.exec(sqlText)[1].replace(/''/g, "'");

test('the SQL body and the template are one text, with no link and the STOP line', () => {
  const ts = tsTemplate(); const sq = sqlTemplate();
  assert.equal(sq, ts);
  assert.doesNotMatch(ts, /https?:\/\/|\bwww\.|[a-z0-9-]+\.[a-z]{2,}\/\S*/i, 'a link in the template');
  assert.match(ts, /reply STOP/);
  assert.equal((ts.match(/\{\{\d\}\}/g) || []).join(','), '{{1}}', 'exactly one variable');
  assert.ok(!/^\{\{|\}\}$/.test(ts.trim()), 'a variable at either end (Meta refuses it)');
  assert.ok(ts.length <= 1024, 'over the 1,024-character template body limit');
  assert.doesNotMatch(ts, /[؀-ۿ]/, 'Arabic to a supplier (28 Sep ruling)');
  assert.doesNotMatch(ts, /\bAI\b/, 'the word AI (profile copy rule)');
  assert.doesNotMatch(ts, /1633275|al furjan|NOL-/i);
});

test('one queue signature, every routine revoked, both new tables service-role only', () => {
  assert.match(sqlText, /drop function if exists public\.fn_wa_supplier_invite_queue\(int, timestamptz\);/);
  for (const sig of ['fn_wa_supplier_invite_brake(text, jsonb)', 'fn_wa_sender_quality_record(text, text, text, jsonb)',
    'fn_wa_supplier_invite_gate(timestamptz)', 'fn_wa_supplier_invite_queue(int, timestamptz, boolean)',
    'fn_marketing_wa_supplier_invites()', 'fn_supplier_whatsapp_optin_record(bigint, text, text, text, text)',
    'fn_marketing_files_wa_invite_reply(text, text, text)', 'fn_wa_consent_question()', 'fn_wa_is_affirmative(text)',
    'fn_wa_optin_rule(text, text, text, text)', 'fn_supplier_whatsapp_optin_obeys_the_rule()',
    'fn_supplier_whatsapp_consent_ask_record(text, text, text)', 'fn_marketing_supplier_outreach_targets(int)',
    'fn_marketing_manual_outreach_targets()']) {
    assert.ok(sqlText.includes(`revoke execute on function public.${sig} from public, anon, authenticated;`), sig);
  }
  for (const t of ['supplier_whatsapp_optin', 'wa_sender_quality_reading', 'supplier_whatsapp_consent_ask']) {
    assert.ok(sqlText.includes(`alter table public.${t} enable row level security;`), t);
    assert.ok(sqlText.includes(`revoke all on public.${t} from anon, authenticated;`), t);
  }
  assert.doesNotMatch(sqlText.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n'), /update public\.app_secrets/i,
    'this file must never write a switch');
});

// A ZZ DEMO lead with a UAE mobile, in the rolled-back transaction only.
const DEMO = (n, opt = true, trade = 'painting') => `
  insert into public.leads (company_name, email, phone_e164, sector)
  values ('ZZ DEMO wa invite ${n}', 'zz-wa-${n}@example.invalid', '+97150000007${n}', '${trade}');
  ${opt ? `insert into public.supplier_whatsapp_optin (lead_id, phone, source, consent_question, consent_answer, evidence)
           select id, phone_e164, 'call_consent_reply', public.fn_wa_consent_question(), 'yes', 'ZZ DEMO probe'
             from public.leads where company_name = 'ZZ DEMO wa invite ${n}';` : ''}`;
const ON = `update public.app_secrets set value = 'true' where key in ('wa_supplier_invite_golive', 'invite_enabled');
  update public.it_watch_finding set status = 'resolved' where detector_key = 'deliverability:supplier_invite_wa';
  insert into public.wa_sender_quality_reading (rating, status, ok) values ('HIGH', 'ONLINE', true);`;
const TUE_NOON = `'2026-10-27 08:00+00'`;   // Tuesday 12:00 Dubai
const SAT_NOON = `'2026-10-31 08:00+00'`;   // Saturday 12:00 Dubai
const q = (at) => `(public.fn_wa_supplier_invite_queue(20, ${at}, true)->>'queued')::int`;
// A demo invitation is captured on insert (zzzz_notifications_demo_capture: status 'suppressed', never handed to
// Twilio), which is what makes these probes incapable of reaching anyone. To measure that the brake and STOP cancel
// what is in flight, the captured demo rows are put in the claimed state send_whatsapp holds them in ('sending').
const CLAIMED = `update public.notifications n set status = 'sending', last_error = null from public.leads l
  where l.id = n.lead_id and n.type = 'supplier_invite_wa' and l.company_name like 'ZZ DEMO wa invite %';`;

test('switched off (production as it stands): nothing queues, real or demo', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(1) + `
    create temp table _b as select count(*) n from public.notifications where type = 'supplier_invite_wa';
    create temp table _o as select public.fn_wa_supplier_invite_queue(20, ${TUE_NOON}, false) real_o,
                                   public.fn_wa_supplier_invite_queue(20, ${TUE_NOON}, true) demo_o;
    select (select (real_o->>'queued')::int from _o) real_q, (select (demo_o->>'queued')::int from _o) demo_q,
           (select (demo_o->>'live')::boolean from _o) live, (select demo_o->'why' from _o)::text why,
           (select count(*) from public.notifications where type = 'supplier_invite_wa') - (select n from _b) as rows;`,
  { label: 'wa invite off', rows: true });
  assert.equal(r.live, false); assert.equal(r.real_q, 0); assert.equal(r.demo_q, 0); assert.equal(Number(r.rows), 0);
  assert.match(r.why, /invite_enabled is not true/, 'the paused campaign holds WhatsApp too: ' + r.why);
});

test('each missing condition holds; all on queues the opted-in demo lead once, with no link', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(1) + DEMO(2, false) + `
    update public.app_secrets set value = 'true' where key = 'wa_supplier_invite_golive';
    update public.app_secrets set value = 'false' where key = 'invite_enabled';
    create temp table _r (k text, v int);
    insert into _r select 'golive_only', ${q(TUE_NOON)};
    ${ON}
    delete from public.wa_sender_quality_reading;
    insert into _r select 'no_quality', ${q(TUE_NOON)};
    insert into public.wa_sender_quality_reading (rating, status, ok) values ('MEDIUM', 'ONLINE', false);
    insert into _r select 'medium', ${q(TUE_NOON)};
    insert into public.wa_sender_quality_reading (rating, status, ok) values ('HIGH', 'ONLINE', true);
    insert into _r select 'saturday', ${q(SAT_NOON)};
    insert into _r select 'night', ${q(`'2026-10-27 15:00+00'`)};
    insert into _r select 'on', ${q(TUE_NOON)};
    insert into _r select 'again', ${q(TUE_NOON)};
    select (select jsonb_object_agg(k, v) from _r)::text res,
           (select count(*) from public.notifications n join public.leads l on l.id = n.lead_id
             where n.type = 'supplier_invite_wa' and l.company_name = 'ZZ DEMO wa invite 2') no_optin_rows,
           (select string_agg(n.body, ' ') from public.notifications n join public.leads l on l.id = n.lead_id
             where n.type = 'supplier_invite_wa' and l.company_name = 'ZZ DEMO wa invite 1') body,
           (select string_agg(n.status, ',') from public.notifications n join public.leads l on l.id = n.lead_id
             where n.type = 'supplier_invite_wa' and l.company_name = 'ZZ DEMO wa invite 1') status;`,
  { label: 'wa invite conditions', rows: true });
  const res = JSON.parse(r.res);
  for (const k of ['golive_only', 'no_quality', 'medium', 'saturday', 'night']) assert.equal(res[k], 0, k + ' queued ' + res[k]);
  assert.equal(res.on, 1, 'all on: the opted-in demo lead, and only it');
  assert.equal(res.again, 0, 'never twice');
  assert.equal(Number(r.no_optin_rows), 0, 'a lead with no opt-in was queued');
  assert.match(r.body, /onboarding painting suppliers/);
  assert.doesNotMatch(r.body, /https?:\/\/|www\./);
  assert.equal(r.status, 'suppressed', 'a demo invitation is captured, never handed to Twilio');
});

// Independent review of #1634 (27 Oct 2026): every case above opts in from the lead's own phone_e164, so they measured
// the case the queue handled. An opt-in is a (lead, number) pair; this one names ANOTHER number.
test('the invitation goes to the number that opted in, never to a lead number nobody opted in from', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(6, false) + ON + `
    insert into public.supplier_whatsapp_optin (lead_id, phone, source, consent_question, consent_answer, evidence)
    select id, '+971500000099', 'email_consent_reply', public.fn_wa_consent_question(), 'yes please',
           'ZZ DEMO probe: said yes to WhatsApp on another number'
      from public.leads where company_name = 'ZZ DEMO wa invite 6';
    create temp table _a as select ${q(TUE_NOON)} first;
    select (select first from _a) first,
           (select string_agg(n.to_phone, ',') from public.notifications n join public.leads l on l.id = n.lead_id
             where n.type = 'supplier_invite_wa' and l.company_name = 'ZZ DEMO wa invite 6') to_phones;`,
  { label: 'wa invite opted-in number', rows: true });
  assert.equal(r.first, 1);
  assert.equal(r.to_phones, '+971500000099', 'sent to ' + r.to_phones + ', not the opted-in number');
});

test('send_whatsapp re-reads the opt-in for the exact number as a marketing row leaves', () => {
  const src = read('supabase/functions/send_whatsapp/index.ts');
  assert.match(src, /from\('supplier_whatsapp_optin'\)\.select\('id'\)\.eq\('phone', String\(n\.to_phone/);
  assert.match(src, /no recorded WhatsApp opt-in for this number/);
});

test('a LOW quality reading brakes: the finding opens, the queued invitation is cancelled, nothing more queues', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(1) + DEMO(3) + ON + `
    create temp table _a as select ${q(TUE_NOON)} first;
    ${CLAIMED}
    create temp table _rec as select public.fn_wa_sender_quality_record('LOW', 'ONLINE', '1K', '{}'::jsonb) rec;
    insert into public.wa_sender_quality_reading (rating, status, ok) values ('HIGH', 'ONLINE', true);   -- recovered
    create temp table _b as select ${q(TUE_NOON)} after_brake;
    select (select first from _a) first, (select (rec->>'ok')::boolean from _rec) rec_ok, (select after_brake from _b) after_brake,
           (select count(*) from public.it_watch_finding where detector_key = 'deliverability:supplier_invite_wa' and status = 'open') open_brake,
           (select count(*) from public.notifications n join public.leads l on l.id = n.lead_id
             where n.type = 'supplier_invite_wa' and l.company_name like 'ZZ DEMO wa invite %' and n.status in ('queued', 'sending')) still_queued,
           (select count(*) from public.notifications n join public.leads l on l.id = n.lead_id
             where n.type = 'supplier_invite_wa' and l.company_name like 'ZZ DEMO wa invite %' and n.status = 'cancelled') cancelled;`,
  { label: 'wa invite quality brake', rows: true });
  assert.equal(r.first, 2);
  assert.equal(r.rec_ok, false);
  assert.equal(Number(r.open_brake), 1);
  assert.equal(Number(r.still_queued), 0, 'the brake cancels what is queued');
  assert.equal(Number(r.cancelled), 2, 'both in-flight demo invitations cancelled (or the check measured nothing)');
  assert.equal(r.after_brake, 0, 'a recovered rating does not lift the brake; a person resolves the finding');
});

test('STOP from an invited number opts the lead out for good and cancels what is queued to it', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(5) + ON + `
    create temp table _a as select ${q(TUE_NOON)} first;
    ${CLAIMED}
    create temp table _s as select public.fn_wa_supplier_invite_opt_out('whatsapp:+971500000075') s;
    create temp table _b as select ${q(TUE_NOON)} again;
    select (select first from _a) first, (select (s->>'invitations_cancelled')::int from _s) cancelled, (select again from _b) again,
           (select whatsapp_opt from public.leads where company_name = 'ZZ DEMO wa invite 5') opt;`,
  { label: 'wa invite STOP', rows: true });
  assert.equal(r.first, 1); assert.equal(r.cancelled, 1); assert.equal(r.opt, 'none'); assert.equal(r.again, 0);
});

// it_engineer, 27 Oct 2026 (safety review before ledger 1373's switch). An opt-in may name a number that is on no lead
// row; before a_stop_from_the_number_a_supplier_opted_in_from_opts_that_supplier_out.sql a STOP from that number marked
// no lead, so the invitation still queued to the person who had just said STOP (measured: queued 1 on main 21640c8db).
const STOP_FIX = read('scripts/sql/a_stop_from_the_number_a_supplier_opted_in_from_opts_that_supplier_out.sql');
test('STOP from a number that is on no lead row, but that a supplier opted in from, stops that supplier', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + STOP_FIX + DEMO(7, false) + ON + `
    insert into public.supplier_whatsapp_optin (lead_id, phone, source, consent_question, consent_answer, evidence)
    select id, '+971500000097', 'call_consent_reply', public.fn_wa_consent_question(), 'yes',
           'ZZ DEMO probe: said yes on a number that is on no lead row'
      from public.leads where company_name = 'ZZ DEMO wa invite 7';
    create temp table _s as select public.fn_wa_supplier_invite_opt_out('whatsapp:+971500000097') s;
    create temp table _a as select ${q(TUE_NOON)} after_stop;
    select (select after_stop from _a) after_stop, (select (s->>'leads_opted_out')::int from _s) opted_out,
           (select whatsapp_opt from public.leads where company_name = 'ZZ DEMO wa invite 7') opt;`,
  { label: 'wa invite STOP from the opted-in number', rows: true });
  assert.equal(r.opted_out, 1, 'the STOP marked no lead');
  assert.equal(r.opt, 'none');
  assert.equal(r.after_stop, 0, 'an invitation queued to a number that had just said STOP');
});

test('the manual outreach list names uninvited, real, unsuppressed suppliers with a public page, and writes nothing', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + `
    create temp table _b as select count(*) n from public.notifications;
    create temp table _t as select public.fn_marketing_manual_outreach_targets() t;
    create temp table _ids as select (x->>'lead_id')::bigint id from _t, jsonb_array_elements(t->'trades') tr, jsonb_array_elements(tr->'targets') x;
    select (select count(*) from _ids) targets,
           (select count(*) from _ids i join public.leads l on l.id = i.id
             where coalesce(l.is_demo, false) or l.invited_at is not null or l.invite_status is not null or coalesce(l.claimed, false)
                or coalesce(l.whatsapp_opt, '') = 'none' or coalesce(l.linkedin, l.instagram, l.facebook, '') = '') bad,
           (select count(*) from public.notifications) - (select n from _b) queued;`,
  { label: 'manual outreach list', rows: true });
  assert.ok(Number(r.targets) > 0, 'an empty list measures nothing');
  assert.equal(Number(r.bad), 0);
  assert.equal(Number(r.queued), 0);
});

// ---- WHAT COUNTS AS AN OPT-IN (founder ledger 1341, 27 Oct 2026): "count an opt-in only when the supplier taps 'Set up
// my page' or answers yes to a question that asks for consent, not from any message a supplier sends" -- "approved".
const optins = (n) => `(select count(*) from public.supplier_whatsapp_optin o join public.leads l on l.id = o.lead_id
  where l.company_name = 'ZZ DEMO wa invite ${n}')`;
const optinSource = (n) => `(select string_agg(o.source, ',') from public.supplier_whatsapp_optin o join public.leads l on l.id = o.lead_id
  where l.company_name = 'ZZ DEMO wa invite ${n}')`;
const ASK = (n) => `public.fn_supplier_whatsapp_consent_ask_record('whatsapp:+97150000007${n}', 'Thanks for your message. ' || public.fn_wa_consent_question(), 'sales_engineer')`;

test('wa_inbound hands the button payload to the one rule, and nothing else in it records an opt-in', () => {
  const src = read('supabase/functions/wa_inbound/index.ts');
  assert.match(src, /rpc\('fn_marketing_files_wa_invite_reply', \{ p_from: From, p_body: Body\.slice\(0, 4000\), p_button_payload: ButtonPayload \|\| null \}\)/);
  assert.doesNotMatch(src, /from\('supplier_whatsapp_optin'\)\.(insert|upsert)/, 'wa_inbound writes opt-ins only through the rule');
  assert.ok(gateTs.includes("{ id: 'supplier_invite_yes', title: 'Set up my page' }"), 'the button id the SQL rule matches');
  assert.ok(sqlText.includes("= 'supplier_invite_yes' then"), 'the SQL rule matches the same payload');
  assert.match(sqlText, /create trigger a00_supplier_whatsapp_optin_obeys_the_rule before insert or update on public\.supplier_whatsapp_optin/);
});

test('"who is this?" never opts in, even with a consent question open, and a later yes to something else does not either', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(4, false) + `
    update public.leads set invited_at = now(), invite_status = 'sent' where company_name = 'ZZ DEMO wa invite 4';
    select set_config('qd.probe_files_demo_handoff', 'on', true);
    create temp table _f as select public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000074', 'Hi, who is this?', null) f;
    create temp table _n0 as select ${optins(4)} n;
    create temp table _a as select ${ASK(4)} a;
    create temp table _g as select public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000074', 'who is this?', null) g;
    create temp table _h as select public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000074', 'yes', null) h;
    select (select f from _f)::text f, (select n from _n0) before_ask, (select (a->>'ok')::boolean from _a) ask_ok,
           ${optins(4)} after_all,
           (select count(*) from public.supplier_whatsapp_consent_ask where phone = '+971500000074' and answer = 'who is this?') closed_by,
           (select (a.detail->>'opted_in') || '|' || (a.detail->>'type') from public.agent_actions a
             where a.id = ((select f from _f)->>'handoff_id')::bigint) handoff;`,
  { label: 'who is this', rows: true });
  const f = JSON.parse(r.f);
  assert.equal(Number(r.before_ask), 0, '"who is this?" recorded an opt-in: ' + r.f);
  assert.equal(r.ask_ok, true);
  assert.equal(Number(r.closed_by), 1, 'the first reply after the ask closes it');
  assert.equal(Number(r.after_all), 0, 'a yes after the consent question was already answered by "who is this?" counted');
  assert.equal(f.due, true, 'the reply still reaches the sales engineer: ' + r.f);
  assert.equal(r.handoff, 'false|invite.reply', 'the handoff says it is not an opt-in');
});

test('the "Set up my page" button opts in; the same words typed, or another button, do not', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(7, false) + DEMO(8, false) + `
    create temp table _x as select
      public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000077', 'Set up my page', 'supplier_invite_yes') tap,
      public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000078', 'Set up my page', null) typed,
      public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000078', 'Main menu', 'menu_main') other;
    select ${optins(7)} tapped, ${optinSource(7)} src,
           (select button_payload from public.supplier_whatsapp_optin o join public.leads l on l.id = o.lead_id
             where l.company_name = 'ZZ DEMO wa invite 7') payload,
           ${optins(8)} typed_or_other;`,
  { label: 'button opt-in', rows: true });
  assert.equal(Number(r.tapped), 1, 'the button did not opt in');
  assert.equal(r.src, 'wa_button'); assert.equal(r.payload, 'supplier_invite_yes');
  assert.equal(Number(r.typed_or_other), 0, 'typed words or another button recorded an opt-in');
});

test('a yes to the consent question opts in, in English and in Arabic; a yes with no question asked does not', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(9, false) + DEMO(3, false) + DEMO(1, false) + `
    create temp table _a as select ${ASK(9)} a9, ${ASK(3)} a3;
    create temp table _x as select
      public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000079', 'Yes please', null) en,
      public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000073', 'نعم، موافق', null) ar,
      public.fn_marketing_files_wa_invite_reply('whatsapp:+971500000071', 'yes', null) unasked;
    select ${optins(9)} en, ${optinSource(9)} en_src, ${optins(3)} ar, ${optins(1)} unasked,
           (select consent_answer from public.supplier_whatsapp_optin o join public.leads l on l.id = o.lead_id
             where l.company_name = 'ZZ DEMO wa invite 3') ar_answer;`,
  { label: 'consent yes', rows: true });
  assert.equal(Number(r.en), 1, 'an English yes to the consent question did not opt in');
  assert.equal(r.en_src, 'wa_consent_reply');
  assert.equal(Number(r.ar), 1, 'an Arabic yes to the consent question did not opt in');
  assert.equal(r.ar_answer, 'نعم، موافق');
  assert.equal(Number(r.unasked), 0, 'a yes with no consent question asked recorded an opt-in');
});

test('the sales engineer\'s writer and a direct insert obey the same rule', { skip: SKIP }, async () => {
  const [r] = await replaySql(sqlText + DEMO(2, false) + `
    create temp table _x as select
      public.fn_supplier_whatsapp_optin_record((select id from public.leads where company_name = 'ZZ DEMO wa invite 2'),
        'email_consent_reply', 'Can we chat on WhatsApp?', 'yes') wrong_q,
      public.fn_supplier_whatsapp_optin_record((select id from public.leads where company_name = 'ZZ DEMO wa invite 2'),
        'email_consent_reply', public.fn_wa_consent_question(), 'maybe later') not_yes;
    create temp table _y as select public.fn_supplier_whatsapp_optin_record((select id from public.leads where company_name = 'ZZ DEMO wa invite 2'),
        'call_consent_reply', public.fn_wa_consent_question(), 'Sure') ok;
    create temp table _d (refused text);
    do $d$ begin
      insert into public.supplier_whatsapp_optin (lead_id, phone, source, evidence)
      select id, '+971500000098', 'wa_consent_reply', 'ZZ DEMO probe: no question, no answer' from public.leads where company_name = 'ZZ DEMO wa invite 2';
      insert into _d values ('NOT REFUSED');
    exception when check_violation then insert into _d values (sqlerrm); end $d$;
    select (select wrong_q->>'ok' from _x) wrong_q, (select not_yes->>'ok' from _x) not_yes, (select ok->>'ok' from _y) ok,
           (select refused from _d) refused, ${optins(2)} n;`,
  { label: 'writers obey the rule', rows: true });
  assert.equal(r.wrong_q, 'false', 'a yes to a question that is not the consent question was recorded');
  assert.equal(r.not_yes, 'false', '"maybe later" was recorded as consent');
  assert.equal(r.ok, 'true');
  assert.match(r.refused, /refused \(ledger 1341\)/, 'a direct insert bypassing the writers was accepted: ' + r.refused);
  assert.equal(Number(r.n), 1);
});

test('what reads as a yes: English and Arabic yes words, never a question or a sentence', { skip: SKIP }, async () => {
  const YES = ['yes', 'Yes!', 'YES please', 'yeah', 'ok', 'Okay, thanks', 'sure', 'Of course', 'go ahead', 'I agree', '👍',
    'نعم', 'أكيد', 'تمام', 'موافق', 'موافقة', 'ايوه', 'طبعاً', 'نعم شكرا',
    // the symbols a yes may carry: a thumbs-up in any skin tone, a tick with its emoji selector, a smile, thanks
    '👍🏻', '✅️', 'ok 👍', 'yes 🙂', 'yes 🙏', 'yes.', 'yes!!', 'yes - thanks', 'نعم، شكرا'];
  const NO = ['who is this?', 'Hi, who is this', 'what is quotesdone', 'yes but who are you', 'ok?', 'no', 'No thanks',
    'not now', 'maybe later', 'STOP', 'hello', 'Set up my page', 'من أنت؟', 'لا', 'ايه', 'مين معي', 'لا شكرا', '', '123',
    // a negative emoji beside a yes is not a yes (independent review of #1634: 'yes 👎' read as a yes)
    'yes 👎', 'ok ❌', 'نعم 🚫',
    // ...and neither is any symbol the rule does not know. The second review of #1634 measured 'yes 🛑', 'yes 🙅',
    // 'ok 😡' and 'yes 🤬' all reading as consent: a list of negative emoji can never be complete, so only a short
    // list of symbols may sit beside a yes and anything else fails closed.
    'yes 🛑', 'yes 🙅', 'yes 🙅‍♂️', 'ok 😡', 'yes 🤬', 'yes ✋', 'نعم 😠', 'yes :(', 'yes 🤔', 'ok 🙄'];
  const arr = (a) => `array[${a.map((s) => `'${s.replace(/'/g, "''")}'`).join(', ')}]::text[]`;
  const [r] = await replaySql(sqlText + `
    select (select coalesce(string_agg(x, ' | '), '') from unnest(${arr(YES)}) x where not public.fn_wa_is_affirmative(x)) missed,
           (select coalesce(string_agg(x, ' | '), '') from unnest(${arr(NO)}) x where public.fn_wa_is_affirmative(x)) wrong;`,
  { label: 'affirmatives', rows: true });
  assert.equal(r.missed, '', 'a yes not read as a yes');
  assert.equal(r.wrong, '', 'read as a yes');
});

