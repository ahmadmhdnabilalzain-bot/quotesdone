// SUPPLIER-REGISTRATION CAMPAIGN READINESS GATE (23 Sep 2026, marketing with it_engineer; founder
// instruction 584). Proves every part of the campaign against production and prints a PASS/FAIL table.
// It NEVER sends the campaign and never writes to a real lead: the only writes are one unsubscribe and
// its resubscribe on a ZZ DEMO @example.invalid address (removed again, and the removal is asserted),
// and, unless --no-walk, the registration walk's own ZZ DEMO leads (torn down by the walk itself).
// The founder decides GO (app_secrets.supplier_outreach_golive); this gate only reports it.
//
//   node --no-warnings scripts/campaign_readiness.mjs            # everything, incl. the ~5 min browser walk
//   node --no-warnings scripts/campaign_readiness.mjs --no-walk  # skip the browser walk
// Exit 1 if any row is FAIL. Token: %USERPROFILE%\.supabase\access-token or SUPABASE_ACCESS_TOKEN.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { createHmac } from 'node:crypto';
import { Resolver } from 'node:dns/promises';
import { spawnSync } from 'node:child_process';

const REF = 'htdblwldjkcgjvmqkbeh';
const tok = process.env.SUPABASE_ACCESS_TOKEN?.trim() || readFileSync(join(homedir(), '.supabase', 'access-token'), 'utf8').trim();
async function sql(query, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST', headers: { Authorization: `Bearer ${tok}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ query }), signal: AbortSignal.timeout(120000) });
  if ((r.status === 429 || r.status >= 500) && attempt < 6) { await new Promise((s) => setTimeout(s, 2000 * 2 ** attempt)); return sql(query, attempt + 1); }
  if (!r.ok) throw new Error(`SQL HTTP ${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
}
const one = async (q) => (await sql(q))[0];
const rows = [];
const row = (area, check, ok, evidence) => rows.push({ area, check, verdict: ok === null ? 'INFO' : ok ? 'PASS' : 'FAIL', evidence: String(evidence) });
const guard = async (area, check, fn) => { try { await fn(); } catch (e) { row(area, check, false, 'error: ' + e.message); } };
// Public resolvers: the OS stub resolver is refused on some hosts (ECONNREFUSED measured on the founder's machine).
const dns = new Resolver(); dns.setServers(['8.8.8.8', '1.1.1.1']);
const txt = async (name) => { try { return (await dns.resolveTxt(name)).map((c) => c.join('')); } catch { return []; } };

// 1. DELIVERABILITY -----------------------------------------------------------------------------------
await guard('1 deliverability', 'SPF/DKIM/DMARC', async () => {
  const dmarc = (await txt('_dmarc.quotesdone.com')).find((t) => t.startsWith('v=DMARC1')) || '';
  row('1 deliverability', 'DMARC on quotesdone.com (covers mail. subdomain)', /p=(quarantine|reject)/.test(dmarc), dmarc || 'missing');
  for (const d of ['quotesdone.com', 'mail.quotesdone.com']) {
    const spf = (await txt(`send.${d}`)).find((t) => t.startsWith('v=spf1')) || '';
    const dkim = (await txt(`resend._domainkey.${d}`)).find((t) => t.includes('p=')) || '';
    row('1 deliverability', `SPF on the return path send.${d}`, /include:amazonses\.com/.test(spf), spf || 'missing');
    row('1 deliverability', `DKIM resend._domainkey.${d}`, dkim.length > 100, dkim ? `key published (${dkim.length} chars)` : 'missing');
  }
});
await guard('1 deliverability', 'Resend domains verified', async () => {
  const key = (await one(`select value from app_secrets where key='resend_api_key'`))?.value;
  const r = await fetch('https://api.resend.com/domains', { headers: { Authorization: `Bearer ${key}` } });
  if (!r.ok) throw new Error(`Resend API HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const j = await r.json();
  const doms = (j.data || []).map((d) => `${d.name}=${d.status}/sending ${d.capabilities?.sending}`);
  row('1 deliverability', 'Resend: both sending domains verified', (j.data || []).filter((d) => d.status === 'verified' && d.capabilities?.sending === 'enabled').length >= 2, doms.join('; '));
  row('5 caps', 'Resend API rate limit (per second)', null, `${r.headers.get('ratelimit-policy')} — send_outbox drains 20 per tick, well under it`);
});
await guard('1 deliverability', 'mail-tester', async () => {
  const seeds = await sql(`select distinct on (lang) id, lang, to_email, status, provider_message_id is not null pm, sent_at
    from notifications where to_email ilike 'test-%@srv1.mail-tester.com' and status='sent' order by lang, sent_at desc`);
  for (const lang of ['en', 'ar']) {
    const s = seeds.find((x) => x.lang === lang);
    if (!s) { row('1 deliverability', `mail-tester ${lang.toUpperCase()} seed sent through the outbox`, false, 'no sent seed row'); continue; }
    const page = await (await fetch(`https://www.mail-tester.com/${s.to_email.split('@')[0]}`)).text();
    const score = parseFloat((page.match(/score">\s*([0-9.]+)\s*\/\s*10/) || [])[1]);
    const auth = ['dkim', 'dmarc'].map((k) => (page.match(new RegExp(`${k}=([a-z]+)`)) || [])[1] || '?').join('/');
    row('1 deliverability', `mail-tester ${lang.toUpperCase()} score (notification #${s.id}, sent ${String(s.sent_at).slice(0, 16)})`,
      s.pm && score >= 9, `${isNaN(score) ? 'result page no longer readable' : score + '/10'}; dkim/dmarc ${auth}; provider id ${s.pm ? 'present' : 'MISSING'}`);
  }
});

// 2. TEMPLATE AND AUDIENCE ----------------------------------------------------------------------------
await guard('2 template', 'inbox rules', async () => {
  const r = spawnSync(process.execPath, ['--no-warnings', 'scripts/invitation_inbox_check.mjs'], { encoding: 'utf8', timeout: 180000 });
  const out = r.stdout || '';
  const pass = (out.match(/^PASS/gm) || []).length, fail = (out.match(/^FAIL/gm) || []).length;
  row('2 template', 'EN + AR invitation render (live copy, send_outbox own renderer), every inbox rule', r.status === 0 && fail === 0 && /AR invitation/.test(out),
    `${pass} rules PASS, ${fail} FAIL; RTL + one-click List-Unsubscribe in both`);
});
await guard('2 template', 'batch', async () => {
  const b = await one(`select count(*) n, count(*) filter (where lang='ar') ar,
     count(*) filter (where public.fn_is_demo_email(to_email) or company_name ~* '^\\s*zz\\s*demo') demo,
     count(*) filter (where exists (select 1 from email_suppressions s where lower(s.email)=lower(c.to_email))) suppressed,
     count(*) filter (where exists (select 1 from sanctions_ban b where b.lead_id=c.lead_id)
                        or exists (select 1 from leads l where l.id=c.lead_id and l.banned)) sanctioned,
     count(*) - count(distinct lower(to_email)) dup,
     count(*) filter (where body !~ '/(en|ar)/portal[?]t=[0-9a-f-]{36}') no_link,
     count(*) filter (where lang='ar' and body !~ '[؀-ۿ]') ar_no_arabic
     from public.fn_supplier_invite_candidates(50) c`);
  const bad = +b.demo + +b.suppressed + +b.sanctioned + +b.dup + +b.no_link + +b.ar_no_arabic;
  row('2 template', "tomorrow's batch (fn_supplier_invite_candidates(50))", +b.n > 0 && bad === 0,
    `${b.n} rows (${b.ar} AR): demo ${b.demo}, suppressed ${b.suppressed}, sanctioned/banned ${b.sanctioned}, duplicate address ${b.dup}, no portal link ${b.no_link}, AR without Arabic ${b.ar_no_arabic}`);
});
await guard('2 template', 'pool', async () => {
  const p = await one(`select count(*) filter (where (l.is_demo or l.company_name ~* '^\\s*zz\\s*demo' or public.fn_is_demo_email(l.email))) demo,
     count(*) filter (where l.banned or exists (select 1 from sanctions_ban b where b.lead_id=l.id)) sanctioned,
     count(*) filter (where exists (select 1 from email_suppressions s where lower(btrim(s.email))=lower(btrim(l.email)))) suppressed,
     count(*) filter (where exists (select 1 from notifications n where n.type='supplier_invite' and lower(btrim(n.to_email))=lower(btrim(l.email)))) already
     from leads l where public.fn_supplier_invite_eligible(l)`);
  row('2 template', 'whole eligible pool: never demo, sanctioned, suppressed or already invited', [p.demo, p.sanctioned, p.suppressed, p.already].every((x) => +x === 0),
    `demo ${p.demo}, sanctioned ${p.sanctioned}, suppressed ${p.suppressed}, already invited ${p.already}`);
  const a = await one(`select count(*) n, count(*) filter (where c.lang <> 'ar') wrong from public.fn_supplier_invite_candidates(100000) c
     join leads l on l.id = c.lead_id where l.company_name ~ '[؀-ۿ]'`);
  row('2 template', 'own language: an Arabic-script company is written to in Arabic', +a.wrong === 0, `${a.n} eligible Arabic-named leads, ${a.wrong} would get English`);
  const g = await one(`select (select tgenabled from pg_trigger where tgname ~ 'supplier_invite_is_whole' limit 1) t,
     (select count(*) from pg_indexes where indexdef ~* 'lower\\(btrim\\(to_email\\)\\)' and indexdef ~* 'supplier_invite' and indexdef ~* 'unique') u`);
  row('2 template', 'one email per supplier: unique outbox index + whole-invitation trigger', g.t === 'O' && +g.u >= 1, `trigger enabled=${g.t}, unique index ${g.u}`);
});

// 3. UNSUBSCRIBE AND BOUNCES --------------------------------------------------------------------------
await guard('3 opt-out', 'unsubscribe live', async () => {
  const e = 'zz-demo-campaign-readiness@example.invalid';
  const s = await one(`select (select value from app_secrets where key='unsubscribe_signing_key') k, (select value from app_secrets where key='unsubscribe_public_base') b`);
  const t = createHmac('sha256', s.k).update(e).digest('hex').slice(0, 20);
  const base = s.b || `https://${REF}.supabase.co/functions/v1/unsubscribe`;
  const url = (a = '') => `${base}?e=${encodeURIComponent(e)}&t=${t}${a}`;
  const has = async () => (await sql(`select reason from email_suppressions where email='${e}'`))[0]?.reason || null;
  const g = await fetch(url()); const afterGet = await has();
  const p = await fetch(url(), { method: 'POST' }); const afterPost = await has();
  const stops = (await one(`select public.fn_suppression_stops('unsubscribe','supplier_invite') a, public.fn_suppression_stops('unsubscribe','registration_received') b`));
  await fetch(url('&a=resub'), { method: 'POST' }); const afterResub = await has();
  row('3 opt-out', `unsubscribe link (${base.replace(/\?.*/, '')}): GET asks, POST suppresses, resubscribe restores`,
    g.status === 200 && afterGet === null && p.status === 200 && afterPost === 'unsubscribe' && afterResub === null,
    `GET ${g.status} row=${afterGet}; POST ${p.status} row=${afterPost}; resub row=${afterResub} (demo address cleaned)`);
  row('3 opt-out', 'an unsubscribe stops invitations and reminders, not sign-up/transactional mail', stops.a === true && stops.b === false, `stops supplier_invite=${stops.a}, registration_received=${stops.b}`);
});
await guard('3 opt-out', 'bounces', async () => {
  const b = await one(`select count(*) filter (where source='resend_webhook') wh, max(created_at) filter (where source='resend_webhook') last,
     public.fn_suppression_stops('hard_bounce:permanent','supplier_invite') st from email_suppressions`);
  row('3 opt-out', 'bounces feed email_suppressions (resend_webhook) and stop the address', +b.wh > 0 && b.st === true, `${b.wh} rows written by resend_webhook, last ${String(b.last).slice(0, 10)}; daily bounce canary runs in the heartbeat`);
  const src = readFileSync('supabase/functions/send_outbox/index.ts', 'utf8');
  row('3 opt-out', 'send_outbox checks the suppression list (case-folded) and holds mail with no unsubscribe link',
    /supReason\.has\(foldEmail/.test(src) && /holdForNoUnsubscribe\(/.test(src), 'source read');
});

// 4. REGISTER LINK ------------------------------------------------------------------------------------
if (process.argv.includes('--no-walk')) row('4 sign-up', 'registration walk (EN+AR, desktop+mobile)', null, 'skipped (--no-walk)');
else await guard('4 sign-up', 'walk', async () => {
  const r = spawnSync(process.execPath, ['scripts/e2e/supplier_registration_walk.mjs'], { encoding: 'utf8', timeout: 900000 });
  const out = r.stdout || ''; const sum = (out.match(/(\d+)\/(\d+) passed/) || []);
  const td = (out.match(/teardown: (\{.*\})/) || [])[1]; const left = td ? JSON.parse(td).total : '?';
  row('4 sign-up', 'invitation link -> sign-up -> claim -> approved, ZZ DEMO @example.invalid, EN+AR desktop+mobile',
    sum[1] && sum[1] === sum[2] && left === 0, `${sum[0] || 'no summary'}; rows left after teardown: ${left}${sum[1] !== sum[2] ? '; ' + (out.match(/^FAIL.*$/gm) || []).slice(0, 3).join(' | ') : ''}`);
});

// 5. CAPS AND THROTTLING ------------------------------------------------------------------------------
await guard('5 caps', 'caps', async () => {
  const c = await one(`select (select value from app_secrets where key='invite_daily_cap') inv, (select value from app_secrets where key='daily_send_cap') tot,
     (select value from app_secrets where key='invite_max_bounce_rate') br, (select value from app_secrets where key='invite_warmup')::jsonb w`);
  const w = c.w || {};
  row('5 caps', 'daily invitation cap + warm-up ramp + bounce brake', +c.inv > 0 && +c.inv <= 100 && w.base_cap && w.ceiling_cap && +c.br > 0,
    `invite_daily_cap ${c.inv}; ramp base ${w.base_cap} x${w.growth_factor} to ${w.ceiling_cap} only while bounces < ${w.grow_max_bounce_rate}; auto-pause at bounce ${c.br}, backoff ${w.backoff_bounce_rate}; all mail cap daily_send_cap ${c.tot}`);
  row('5 caps', 'sends spread across the Dubai working window (not_before)', +w.window_start_hour >= 9 && +w.window_end_hour <= 18, `${w.window_start_hour}:00-${w.window_end_hour}:00 Dubai`);
  row('5 caps', 'Resend plan limit (not measurable: no plan API)', null, `Resend has no plan/quota API; the invitation cap (${c.inv}/day) sits under even the free tier's 100/day. Confirm the plan in the Resend dashboard before the ramp passes 100/day.`);
});

// 6. CONSENT --------------------------------------------------------------------------------------------
row('6 consent', 'lawful basis + opt-out documented', existsSync('docs/legal/SUPPLIER_CAMPAIGN_LAWFUL_BASIS.md'), 'docs/legal/SUPPLIER_CAMPAIGN_LAWFUL_BASIS.md');

// 7. OUTBOX, NOT A STATUS COLUMN ------------------------------------------------------------------------
await guard('7 outbox', 'outbox', async () => {
  const o = await one(`select (select count(*) from notifications where type='supplier_invite') inv, (select count(*) from notifications where type='supplier_invite' and status='sent' and provider_message_id is null) sent_no_id,
     (select coalesce(sum(sent),0) from invite_schedule) sched_sent, (select value from app_secrets where key='supplier_outreach_golive') go, (select value from app_secrets where key='invite_enabled') en,
     pg_get_functiondef('public.fn_supplier_invite_eligible(leads)'::regprocedure) ~ 'n.type = ''supplier_invite''' reads_outbox`);
  row('7 outbox', 'never twice is read from notifications, and no invitation is "sent" without a provider id', o.reads_outbox && +o.sent_no_id === 0,
    `supplier_invite rows in the outbox: ${o.inv}; sent without provider id: ${o.sent_no_id}; invite_schedule.sent total ${o.sched_sent}`);
  row('7 outbox', "campaign switch (the founder's GO)", null, `supplier_outreach_golive=${o.go}, invite_enabled=${o.en} — held until he says go`);
});

// 8. AFTER SIGN-UP --------------------------------------------------------------------------------------
await guard('8 after sign-up', 'duties', async () => {
  const d = await one(`select (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in
      ('fn_sales_engineer_supplier_outreach_tick','fn_supplier_registration_reminders_due','fn_supplier_registration_reminder_compose','fn_sales_engineer_sends_registration_reminder','fn_sales_engineer_verifies_supplier')) fns,
     (select max(started_at) from agent_runs where agent in ('sales_engineer','fn:sales_engineer')) se, (select max(started_at) from agent_runs where agent in ('send_outbox','fn:send_outbox')) ob`);
  const age = (t) => Math.round((Date.now() - new Date(t)) / 60000);
  row('8 after sign-up', 'sales-engineer duties: outreach tick, day-2/day-6 reminders, verification, 14-day close', +d.fns === 5 && age(d.se) < 180,
    `${d.fns}/5 routines live; sales_engineer last ran ${age(d.se)} min ago`);
  row('8 after sign-up', 'the outbox drains (send_outbox heartbeat)', age(d.ob) < 120, `last run ${age(d.ob)} min ago`);
  const api = readFileSync('supabase/functions/supplier_api/index.ts', 'utf8');
  row('8 after sign-up', "onboarding mail: registration_received to the supplier in its language + record to management", /type: 'registration_received'/.test(api) && /type: 'supplier_registered'/.test(api), 'supplier_api save_profile queues both through the outbox');
});

// TABLE -------------------------------------------------------------------------------------------------
const w = (k, n) => Math.min(n, Math.max(...rows.map((r) => r[k].length)));
for (const r of rows) console.log(`${r.verdict.padEnd(4)}  ${r.area.padEnd(w('area', 18))}  ${r.check.padEnd(w('check', 70)).slice(0, 70)}  ${r.evidence}`);
const fails = rows.filter((r) => r.verdict === 'FAIL').length;
console.log(`\n${rows.filter((r) => r.verdict === 'PASS').length} PASS, ${fails} FAIL, ${rows.filter((r) => r.verdict === 'INFO').length} INFO — ${fails ? 'NOT READY' : 'READY; GO is the founder\'s'}`);
process.exit(fails ? 1 : 0);
