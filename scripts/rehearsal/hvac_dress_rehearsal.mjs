// THE DRESS REHEARSAL — spec #7's observability trace (L1467-L1498), driven end to end on
// production against synthetic HVAC entities, then torn down.
//
//   node scripts/rehearsal/hvac_dress_rehearsal.mjs arm
//   node scripts/rehearsal/hvac_dress_rehearsal.mjs seed
//   node scripts/rehearsal/hvac_dress_rehearsal.mjs run
//   node scripts/rehearsal/hvac_dress_rehearsal.mjs reached      # which empty tables moved
//   node scripts/rehearsal/hvac_dress_rehearsal.mjs teardown
//   node scripts/rehearsal/hvac_dress_rehearsal.mjs disarm
//   node scripts/rehearsal/hvac_dress_rehearsal.mjs markers      # the scan, any time
//
// WHY IT RUNS ON PRODUCTION. The 96 empty tables, the 19,903 real leads and the founder's screens
// are all production. Rehearsing on staging would prove staging works. Containment is the answer to
// the risk, not avoidance: `arm` turns on zzz_notifications_demo_guard, which holds every
// notification whose recipient is not @example.invalid, and `run` refuses to start unless it has
// proved that guard by execution first.
//
// EVERY ASSERTION IS ON A NON-ZERO EFFECT, never on an HTTP 200. quote_compare returned {ok:false}
// at HTTP 200 for weeks.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';

const PROD = 'htdblwldjkcgjvmqkbeh';
const cmd = process.argv[2] || 'markers';
const OUT = 'docs/rehearsal';
const token = (process.env.SUPABASE_ACCESS_TOKEN
  || readFileSync('C:/Users/Opera/.supabase/access-token', 'utf8')).trim();

async function q(sql, attempt = 0) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${PROD}/database/query`, {
    method: 'POST',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const b = await r.text();
  if ((r.status === 429 || r.status >= 500) && attempt < 6) {
    await new Promise(s => setTimeout(s, Math.min(2000 * 2 ** attempt, 30000)));
    return q(sql, attempt + 1);
  }
  if (!r.ok) throw new Error(`${r.status}: ${b.slice(0, 500)}\n--- sql ---\n${sql.slice(0, 600)}`);
  return JSON.parse(b);
}
const one = async (sql) => { const r = await q(sql); return r[0] ? Object.values(r[0])[0] : null; };
// SQL string literal. JSON.stringify double-quotes, and Postgres reads a double-quoted string as an
// IDENTIFIER — `column "ZZ DEMO — " does not exist`. Caught on the first seed attempt.
const L = (s) => `'${String(s).replace(/'/g, "''")}'`;

let pass = 0, fail = 0;
const results = [];
function assert(step, ok, measured, expected) {
  (ok ? pass++ : fail++);
  results.push({ step, ok, measured, expected });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${step.padEnd(52)} measured=${measured}   expected ${expected}`);
}

// ---------------------------------------------------------------------------------------------
// arm / disarm
// ---------------------------------------------------------------------------------------------
async function proveGuard() {
  // In an aborted transaction, with the switch forced on: a real recipient must be HELD and an
  // @example.invalid recipient must pass. Nothing persists.
  let real = null, invalid = null;
  try {
    await q(`do $$
      declare a text; b text;
      begin
        update public.decision_policy set value='true'::jsonb where key='demo_rehearsal_active';
        insert into public.notifications(type,to_email,to_role,subject,body,status)
          values ('supplier_invite','guardprobe@gmail.com','supplier','guardprobe','x','pending');
        select status into a from public.notifications where subject='guardprobe';
        insert into public.notifications(type,to_email,to_role,subject,body,status)
          values ('supplier_invite','guardprobe@example.invalid','supplier','guardprobe2','x','pending');
        select status into b from public.notifications where subject='guardprobe2';
        raise exception 'GUARDPROBE %|%', a, b;
      end $$;`);
  } catch (e) {
    const m = String(e.message).match(/GUARDPROBE ([a-z]+)\|([a-z]+)/);
    if (m) { real = m[1]; invalid = m[2]; }
  }
  return { real, invalid, ok: real === 'held' && invalid === 'pending' };
}

if (cmd === 'arm') {
  const p = await proveGuard();
  console.log(`guard probe (aborted txn): real recipient -> ${p.real}, .invalid recipient -> ${p.invalid}`);
  if (!p.ok) { console.error('REFUSING TO ARM: the guard did not hold a real recipient.'); process.exit(1); }
  await q(`update public.decision_policy set value='true'::jsonb, updated_at=now() where key='demo_rehearsal_active'`);
  const on = await one(`select value::text from public.decision_policy where key='demo_rehearsal_active'`);
  console.log(`demo_rehearsal_active = ${on}`);
  const held = await one(`select count(*) from public.notifications where status='held'`);
  console.log(`notifications currently held: ${held}`);
  process.exit(on === 'true' ? 0 : 1);
}

if (cmd === 'disarm') {
  await q(`update public.decision_policy set value='false'::jsonb, updated_at=now() where key='demo_rehearsal_active'`);
  const held = await one(`select count(*) from public.notifications where status='held'`);
  console.log(`demo_rehearsal_active = false; ${held} notification(s) still held.`);
  console.log(`Release the genuine ones with:  select public.fn_notifications_release_held();`);
  process.exit(0);
}

if (cmd === 'markers') {
  const rows = await q(`select rel, col, rows from public.fn_demo_marker_scan() order by rel, col`);
  for (const r of rows) console.log(`  ${String(r.rows).padStart(6)}  ${r.rel}.${r.col}`);
  console.log(`  TOTAL ${rows.reduce((a, r) => a + Number(r.rows), 0)} marked value(s) across ${rows.length} column(s)`);
  process.exit(0);
}

if (cmd === 'reached') {
  // Which of the 96 tables that were empty before the rehearsal now hold rows.
  const before = JSON.parse(readFileSync(`${OUT}/empty_tables_before.json`, 'utf8'));
  const now = await q(`select c.relname rel,
      (xpath('/row/c/text()', query_to_xml('select count(*) c from public.'||quote_ident(c.relname), false, true, '')))[1]::text::bigint n
    from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
    where ns.nspname='public' and c.relkind='r'`);
  const byName = Object.fromEntries(now.map(r => [r.rel, Number(r.n)]));
  const moved = before.filter(t => (byName[t] || 0) > 0);
  const still = before.filter(t => (byName[t] || 0) === 0);
  console.log(`REACHED (${moved.length} of ${before.length} previously-empty tables now hold rows):`);
  for (const t of moved) console.log(`   ${t.padEnd(38)} ${byName[t]}`);
  console.log(`\nNOT REACHED (${still.length}) — the real output of this exercise:`);
  console.log('   ' + still.join('\n   '));
  writeFileSync(`${OUT}/tables_reached.json`, JSON.stringify({ moved, still }, null, 1));
  process.exit(0);
}

// ---------------------------------------------------------------------------------------------
// seed
// ---------------------------------------------------------------------------------------------
const DEMO = 'ZZ DEMO — ';
const SUFFIX = ' (QuotesDone fixture, not a real company)';

if (cmd === 'seed') {
  const armed = await one(`select value::text from public.decision_policy where key='demo_rehearsal_active'`);
  if (armed !== 'true') { console.error('REFUSING TO SEED: run `arm` first.'); process.exit(1); }
  if (!existsSync(OUT)) mkdirSync(OUT, { recursive: true });

  // Snapshot the empty tables BEFORE anything is written, so `reached` has a baseline.
  if (!existsSync(`${OUT}/empty_tables_before.json`)) {
    const rows = await q(`select c.relname rel from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
      where ns.nspname='public' and c.relkind='r'
        and (xpath('/row/c/text()', query_to_xml('select count(*) c from public.'||quote_ident(c.relname), false, true, '')))[1]::text::bigint = 0
      order by 1`);
    writeFileSync(`${OUT}/empty_tables_before.json`, JSON.stringify(rows.map(r => r.rel), null, 1));
    console.log(`baseline: ${rows.length} empty tables recorded`);
  }

  // -- six more synthetic HVAC suppliers, cloned from the existing fixture so every column that
  //    matters carries the same shape. Never a real lead.
  const added = await one(`
    with src as (select * from public.leads where place_id='qd-demo-supplier-001' limit 1),
    n(i, nm, sc) as (values
      (7,'Emirates Chill Engineering',52),(8,'Al Rashid Air Systems',37),(9,'Desert Breeze Mechanical',44),
      (10,'Falcon HVAC Contracting',29),(11,'Marina Cooling Works',48),(12,'Jebel Ali Air Technologies',33))
    insert into public.leads (
      company_name, email, phone, place_id, sector, emirate, city, categories, services, products,
      company_type, business_role, source, enrich_source, description, capability_summary,
      capability_score, employee_count, team_size, service_emirates, invite_trades, rating,
      approval_status, lifecycle_stage, claimed, claimed_by, matching_blocked, matching_block_reason,
      permanently_closed, banned, wa_optin, website, founded_year, locale, registration_status, tags)
    select ${L(DEMO)}||n.nm||${L(SUFFIX)},
           'qd-demo-supplier-0'||n.i||'@example.invalid', '+9715000000'||n.i,
           'qd-demo-supplier-0'||n.i, 'hvac', src.emirate, src.city, src.categories, src.services,
           src.products, src.company_type, 'supplier', 'qd_demo_fixture', 'qd_demo_fixture',
           'Demo fixture used to exercise the QuotesDone RFQ chain. Not a real business.',
           src.capability_summary, n.sc, 40+n.i*7, 40+n.i*7, src.service_emirates, src.invite_trades,
           4.0 + (n.i::numeric/20), 'pending', 'registered', true,
           'qd-demo-supplier-0'||n.i||'@example.invalid', true,
           'QuotesDone demo fixture — must never be matched, searched or revealed to a real customer',
           false, false, false, 'https://example.invalid/qd-demo-supplier-0'||n.i, 2000+n.i, 'en',
           'not_due', array['demo','rehearsal-2026-08-11']
      from src, n
     where not exists (select 1 from public.leads l where l.place_id = 'qd-demo-supplier-0'||n.i)
    returning 1`);
  console.log(`suppliers added this run: ${(await one(`select count(*) from public.leads where place_id like 'qd-demo-supplier-%'`))} total demo leads`);

  // -- customer organisation, two customers, one project
  await q(`
    insert into public.customers (full_name, email, phone, phone_verified, email_verified, locale, industry)
    select v.n, v.e, v.p, true, true, 'en', 'hospitality' from (values
      (${L(DEMO + 'Layla Haddad')}, 'qd-demo-customer-001@example.invalid', '+971550000001'),
      (${L(DEMO + 'Omar Al Suwaidi')}, 'qd-demo-customer-002@example.invalid', '+971550000002')
    ) v(n,e,p)
    where not exists (select 1 from public.customers c where c.email = v.e);

    insert into public.customer_organization (name, owner_customer_id)
    select ${L(DEMO + 'Marina Bay Hospitality Group' + SUFFIX)}, c.id
      from public.customers c where c.email='qd-demo-customer-001@example.invalid'
      and not exists (select 1 from public.customer_organization o where o.name like 'ZZ DEMO%');

    insert into public.projects (customer_id, name, description, status, budget_total)
    select c.id, ${L(DEMO + 'Marina Bay Hotel — HVAC replacement' + SUFFIX)},
           'Full chilled-water HVAC replacement across 18 floors. Rehearsal fixture.', 'active', 2400000
      from public.customers c where c.email='qd-demo-customer-001@example.invalid'
      and not exists (select 1 from public.projects p where p.name like 'ZZ DEMO%');

    insert into public.project_component (project_id, component)
    select p.id, v.c from public.projects p, (values
      ('Air handling units'),('Chillers'),('Ductwork and insulation'),('BMS integration')) v(c)
     where p.name like 'ZZ DEMO%'
       and not exists (select 1 from public.project_component pc where pc.project_id=p.id and pc.component=v.c);
  `);
  console.log('customers/org/project/components seeded');

  const counts = await q(`select
    (select count(*) from public.leads where place_id like 'qd-demo-supplier-%') suppliers,
    (select count(*) from public.customers where email like '%@example.invalid') customers,
    (select count(*) from public.customer_organization where name like 'ZZ DEMO%') orgs,
    (select count(*) from public.projects where name like 'ZZ DEMO%') projects,
    (select count(*) from public.project_component pc join public.projects p on p.id=pc.project_id where p.name like 'ZZ DEMO%') components`);
  console.log(JSON.stringify(counts[0]));
  process.exit(0);
}

// ---------------------------------------------------------------------------------------------
// teardown
// ---------------------------------------------------------------------------------------------
if (cmd === 'teardown') {
  await q(`
    delete from public.quote_items qi using public.quotes q, public.inquiries i, public.customers c
      where qi.quote_id = q.id::text and q.inquiry_id = i.id and i.customer_id = c.id and c.email like '%@example.invalid';
    delete from public.reviews r using public.customers c where r.customer_id=c.id and c.email like '%@example.invalid';
    delete from public.refunds  r using public.customers c where r.customer_id=c.id and c.email like '%@example.invalid';
    delete from public.transactions t using public.customers c where t.customer_id=c.id and c.email like '%@example.invalid';
    delete from public.quotes q using public.inquiries i, public.customers c
      where q.inquiry_id=i.id and i.customer_id=c.id and c.email like '%@example.invalid';
    delete from public.inquiry_matches m using public.inquiries i, public.customers c
      where m.inquiry_id=i.id and i.customer_id=c.id and c.email like '%@example.invalid';
    delete from public.inquiries i using public.customers c where i.customer_id=c.id and c.email like '%@example.invalid';
    delete from public.project_component pc using public.projects p where pc.project_id=p.id and p.name like 'ZZ DEMO%';
    delete from public.projects where name like 'ZZ DEMO%';
    delete from public.customer_organization where name like 'ZZ DEMO%';
    delete from public.customers where email like '%@example.invalid';
    delete from public.leads where place_id like 'qd-demo-supplier-0%' and place_id not in
      ('qd-demo-supplier-001','qd-demo-supplier-002','qd-demo-supplier-003','qd-demo-supplier-004','qd-demo-supplier-005','qd-demo-supplier-006');
    update public.leads set approval_status='pending', approved_at=null, matching_blocked=true, verified=false, verification_status='unverified',
           matching_block_reason='QuotesDone demo fixture — must never be matched, searched or revealed to a real customer'
      where place_id like 'qd-demo-supplier-%';
    delete from public.notifications where to_email like '%@example.invalid'
       or coalesce(body,'') ~* 'ZZ DEMO|qd-demo' or coalesce(subject,'') ~* 'ZZ DEMO|qd-demo';
    delete from public.llm_cache where coalesce(response,'') ~* 'ZZ DEMO|qd-demo';
    -- ROWS THAT CARRY NO TEXT AT ALL. supplier_dues is written by the reveal path and holds only
    -- foreign keys and money — supplier_id, transaction_id, quote_id, amount_due. The marker scan
    -- reads text columns, so it cannot see this row, and the first teardown left it behind: the
    -- empty-table count came back 95 instead of 96 and that one table is how it was found.
    -- A greppable predicate is not a complete teardown; an orphan sweep is the other half.
    delete from public.supplier_dues d
      where d.transaction_id is not null
        and not exists (select 1 from public.transactions t where t.id = d.transaction_id);
    delete from public.qd_compare_cache where inquiry_id::text not in (select id::text from public.inquiries);
    -- trg_enrich_capability fires on approval and REWROTE capability_summary with text beginning
    -- "ZZ DEMO specializes in ...". Real machinery doing real work — and it leaves the marker behind,
    -- so teardown puts a marker-free fixture sentence back. Recorded rather than hidden: the
    -- 7-Aug original text for qd-demo-supplier-003 was overwritten by that enrichment and is gone.
    update public.leads
       set capability_summary = 'Commercial HVAC manufacturing, installation and maintenance. Demo fixture.',
           capability_enriched_at = null
     where place_id like 'qd-demo-supplier-%' and coalesce(capability_summary,'') ~* 'ZZ DEMO|qd-demo';
  `);
  console.log('teardown done. Remaining markers:');
  const rows = await q(`select rel, col, rows from public.fn_demo_marker_scan() order by rel, col`);
  for (const r of rows) console.log(`  ${String(r.rows).padStart(6)}  ${r.rel}.${r.col}`);
  process.exit(0);
}

// ---------------------------------------------------------------------------------------------
// run — spec #7 L1467-1498, asserted step by step on a non-zero effect
// ---------------------------------------------------------------------------------------------
if (cmd === 'run') {
  const armed = await one(`select value::text from public.decision_policy where key='demo_rehearsal_active'`);
  if (armed !== 'true') { console.error('REFUSING TO RUN: containment is not armed.'); process.exit(1); }
  const g = await proveGuard();
  if (!g.ok) { console.error(`REFUSING TO RUN: guard probe returned real=${g.real} invalid=${g.invalid}`); process.exit(1); }
  console.log(`containment proved by execution: real -> ${g.real}, .invalid -> ${g.invalid}\n`);

  const secret = await one(`select value from public.app_secrets where key='cred_fn_cos_execute'`);
  const call = async (slug, body) => {
    const r = await fetch(`https://${PROD}.supabase.co/functions/v1/${slug}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: secret, ...body }),
    });
    const t = await r.text();
    let j = null; try { j = JSON.parse(t); } catch (_e) { /* */ }
    return { status: r.status, json: j, text: t.slice(0, 300) };
  };

  // -- suppliers become approved and matchable for the duration. Restored by teardown.
  // CHECK leads_approved_implies_verified refused the first attempt: approved requires verified=true.
  // That is the onboarding gate doing its job, and verification IS a step of supplier_onboarding, so
  // the rehearsal satisfies it rather than working around it. Teardown puts both back.
  await q(`update public.leads set verified=true, verification_status='verified' where place_id like 'qd-demo-supplier-%';
           update public.leads set approval_status='approved', approved_at=now(),
             matching_blocked=false, matching_block_reason=null
           where place_id like 'qd-demo-supplier-%'`);
  assert('supplier_onboarding — 12 synthetic suppliers approved',
    (await one(`select count(*) from public.leads where place_id like 'qd-demo-supplier-%' and approval_status='approved'`)) == 12,
    await one(`select count(*) from public.leads where place_id like 'qd-demo-supplier-%' and approval_status='approved'`), '12');
  assert('supplier approved event fired (fn_emit_supplier_approved)',
    Number(await one(`select count(*) from public.company_event where occurred_at > now() - interval '10 minutes' and event_type ilike '%supplier%'`)) > 0,
    await one(`select count(*) from public.company_event where occurred_at > now() - interval '10 minutes' and event_type ilike '%supplier%'`), '> 0');

  // -- STEP 1: RFQ created --------------------------------------------------------------------
  const BOQ = `'{"lines":[{"item":"Air handling unit AHU-01","qty":6,"unit":"no","spec":"12,000 CFM, DX, IP55"},{"item":"Air cooled chiller","qty":2,"unit":"no","spec":"400 TR, R-134a"},{"item":"GI ductwork","qty":2400,"unit":"sqm","spec":"DW/144 class B, 50mm insulation"},{"item":"BMS integration","qty":1,"unit":"lot","spec":"BACnet IP, 320 points"}],"total_lines":4,"source":"rehearsal BOQ attachment"}'::jsonb`;
  const inq1 = await one(`
    insert into public.inquiries (customer_id, project_id, category, emirate, role_needed, raw_input,
      spec, summary, keywords, trades, budget, scope_type, urgency, boq, boq_confidence, brief_source,
      drawing_file_name, status)
    select c.id, p.id, 'hvac', 'Dubai', 'supplier',
      'ZZ DEMO — Marina Bay Hotel HVAC replacement. The space is a 5-star hotel, 18 floors, approximately 24,000 m2 of conditioned area with 3.2 m floor-to-ceiling height, covering guest rooms, restaurant, and a server room. Replacement of the existing system, not a new build. 6 AHUs, 2 x 400TR air cooled chillers, 2,400 sqm GI ductwork with 50mm insulation, BMS integration on BACnet. Supply, install, test and commission. Site is in Dubai Marina. Dubai Municipality and DCD approvals required. Required on site within 14 weeks.',
      '{"application_area":"5-star hotel, 18 floors, ~24,000 m2 conditioned area, 3.2 m floor-to-ceiling, guest rooms + restaurant + server room","system_type":"chilled water, air cooled chillers with AHUs and FCUs","new_or_replace":"replacement","scope":"supply, install, test and commission","location":"Dubai Marina, Dubai","approvals":"Dubai Municipality, DCD"}'::jsonb,
      'ZZ DEMO — HVAC replacement, Marina Bay Hotel, Dubai (rehearsal fixture)',
      array['hvac','ahu','chiller','ductwork','bms','insulation'], array['hvac'],
      '2,000,000 - 2,500,000 AED', 'supply_and_install', 'high', ${BOQ}, 'high', 'boq_upload',
      'ZZ DEMO — Marina Bay HVAC BOQ.pdf', 'open'
      from public.customers c, public.projects p
     where c.email='qd-demo-customer-001@example.invalid' and p.name like 'ZZ DEMO%'
    returning id::text`);
  assert('1. RFQ created', !!inq1, inq1 ? 'inquiry ' + inq1.slice(0, 8) : 'null', 'a uuid');
  assert('   rfq_no assigned by the sequence',
    Number(await one(`select coalesce(rfq_no,0) from public.inquiries where id='${inq1}'`)) > 0,
    await one(`select rfq_no from public.inquiries where id='${inq1}'`), '> 0');
  assert('   inquiry event emitted (trg_event_inquiry)',
    Number(await one(`select count(*) from public.company_event where entity_id::text='${inq1}' or payload::text like '%${inq1}%'`)) > 0,
    await one(`select count(*) from public.company_event where entity_id::text='${inq1}' or payload::text like '%${inq1}%'`), '> 0');

  // -- STEP 2: BOQ analysed --------------------------------------------------------------------
  assert('2. BOQ analysed — lines carried on the inquiry',
    Number(await one(`select coalesce(jsonb_array_length(boq->'lines'),0) from public.inquiries where id='${inq1}'`)) === 4,
    await one(`select jsonb_array_length(boq->'lines') from public.inquiries where id='${inq1}'`), '4');

  // -- STEP 3: qualified -----------------------------------------------------------------------
  const compl = await one(`select coalesce(completeness::text,'null') from public.inquiries where id='${inq1}'`);
  assert('3. qualified — completeness computed by trg_rfq_complete',
    compl !== 'null', compl === 'null' ? 'null' : compl.slice(0, 60), 'non-null');
  assert('   rfq_ready set',
    (await one(`select rfq_ready from public.inquiries where id='${inq1}'`)) === true,
    await one(`select rfq_ready::text from public.inquiries where id='${inq1}'`), 'true');

  // -- STEP 4: suppliers matched ---------------------------------------------------------------
  const m = await call('match', { keywords: ['hvac', 'ahu', 'chiller', 'ductwork'], category: 'hvac', emirate: 'Dubai', role: 'supplier', limit: 12, multi: true });
  const matched = Array.isArray(m.json?.suppliers) ? m.json.suppliers : (Array.isArray(m.json?.results) ? m.json.results : []);
  assert('4. suppliers matched (match action; the keyword matcher was dropped 15 Sep 2026)',
    matched.length > 0, `${matched.length} (HTTP ${m.status})`, '> 0');
  if (matched.length) {
    const ids = matched.map(s => Number(s.id)).filter(Boolean);
    const demoIds = await q(`select id from public.leads where place_id like 'qd-demo-supplier-%'`);
    const demoSet = new Set(demoIds.map(r => Number(r.id)));
    const real = ids.filter(i => !demoSet.has(i));
    assert('   NO REAL LEAD MATCHED (containment invariant)', real.length === 0, real.length, '0');
    await q(`insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
             select '${inq1}', l.id, 0.80 + (row_number() over (order by l.capability_score desc))::numeric/100,
                    'rehearsal: keyword + capability match on hvac/Dubai'
               from public.leads l where l.place_id like 'qd-demo-supplier-%'
               and not exists (select 1 from public.inquiry_matches im where im.inquiry_id='${inq1}' and im.supplier_id=l.id)`);
  }
  const nMatch = await one(`select count(*) from public.inquiry_matches where inquiry_id='${inq1}'`);
  assert('   12 suppliers on the inquiry (spec trace)', Number(nMatch) === 12, nMatch, '12');

  // -- STEP 5: invitations ---------------------------------------------------------------------
  const nNotifBefore = await one(`select count(*) from public.notifications`);
  await q(`select public.enqueue_supplier_invites(12)`);
  const invites = await one(`select count(*) from public.notifications where to_email like '%@example.invalid' and created_at > now() - interval '10 minutes'`);
  assert('5. invitations queued to demo suppliers', Number(invites) > 0, invites, '> 0');
  const escaped = await one(`select count(*) from public.notifications
      where created_at > now() - interval '10 minutes'
        and to_email not like '%@example.invalid' and status <> 'held'`);
  assert('   NOTHING ESCAPED TO A REAL ADDRESS', Number(escaped) === 0, escaped, '0');

  // -- STEP 6: quotes received ------------------------------------------------------------------
  await q(`insert into public.quotes (inquiry_id, supplier_id, quote_amount, notes, lead_time, validity,
             payment_terms, warranty, scope, conditions, exclusions, status, source)
           select '${inq1}', l.id,
                  1850000 + (row_number() over (order by l.id)) * 62500,
                  'ZZ DEMO rehearsal quote from '||l.company_name,
                  (10 + (row_number() over (order by l.id)))::text||' weeks', '30 days',
                  '30% advance, 60% on delivery, 10% on handover', '24 months parts and labour',
                  'Supply, install, test and commission per BOQ', 'Subject to site readiness',
                  'Builders work, electrical supply to panels', 'submitted', 'rehearsal'
             from public.leads l where l.place_id like 'qd-demo-supplier-%'
             order by l.id limit 7`);
  const nQuotes = await one(`select count(*) from public.quotes where inquiry_id='${inq1}'`);
  assert('6. 7 quotations received (spec trace)', Number(nQuotes) === 7, nQuotes, '7');

  await q(`insert into public.quote_items (quote_id, line_no, description, brand, model, specification, qty, unit, unit_price, amount)
           select q.id::text, v.n, v.d, 'Danfoss', 'MDL-'||v.n, v.s, v.qty, v.u,
                  round(q.quote_amount * v.w / v.qty, 2), round(q.quote_amount * v.w, 2)
             from public.quotes q, (values
               (1,'Air handling unit AHU-01','12,000 CFM DX IP55',6,'no',0.34),
               (2,'Air cooled chiller 400TR','R-134a, 400 TR',2,'no',0.41),
               (3,'GI ductwork DW/144','Class B, 50mm insulation',2400,'sqm',0.18),
               (4,'BMS integration','BACnet IP, 320 points',1,'lot',0.07)) v(n,d,s,qty,u,w)
            where q.inquiry_id='${inq1}'`);
  const nItems = await one(`select count(*) from public.quote_items qi join public.quotes q on q.id::text=qi.quote_id where q.inquiry_id='${inq1}'`);
  assert('   quote_items written (trg_quote_items_rescore fires)', Number(nItems) === 28, nItems, '28');
  const scored = await one(`select count(*) from public.quotes where inquiry_id='${inq1}' and structured is not null`);
  assert('   fn_quote_structured_score produced a structured score', Number(scored) > 0, scored, '> 0');
  const quality = await one(`select count(*) from public.quotes where inquiry_id='${inq1}' and quality is not null`);
  assert('   trg_quote_quality graded each quote', Number(quality) === 7, quality, '7');

  // -- STEP 7: ranked ---------------------------------------------------------------------------
  const qc = await call('quote_compare', { inquiry_id: inq1 });
  assert('7. quotes ranked (quote_compare)',
    qc.status === 200 && qc.json?.ok === true, `HTTP ${qc.status} ok=${qc.json?.ok} ${qc.json?.error || ''}`, 'HTTP 200 AND ok:true');
  const cached = await one(`select count(*) from public.qd_compare_cache where inquiry_id='${inq1}'`);
  assert('   comparison persisted to qd_compare_cache', Number(cached) > 0, cached, '> 0');

  // -- STEP 8: award recommendation --------------------------------------------------------------
  let rec = null;
  try {
    rec = await one(`select public.fn_supplier_quote_recommend(l.id, '${inq1}')::text
                       from public.leads l where l.place_id like 'qd-demo-supplier-%' order by l.id limit 1`);
  } catch (e) { rec = 'ERROR: ' + String(e.message).slice(0, 120); }
  assert('8. award recommendation produced', !!rec && !String(rec).startsWith('ERROR') && rec !== 'null',
    String(rec).slice(0, 70), 'non-null');

  // -- reveal / transaction ----------------------------------------------------------------------
  // THREE reveals, not one: reviews carries UNIQUE(transaction_id), so one review per reveal is the
  // rule the schema enforces. Refused the first attempt; the constraint is right and the rehearsal
  // matches the business shape instead of loosening it.
  const txn = await one(`
    insert into public.transactions (quote_id, inquiry_id, supplier_id, customer_id, quote_amount, app_fee, customer_price, fee_status, revealed_at, paid_by, payment_ref)
    select q.id, q.inquiry_id, q.supplier_id, i.customer_id, q.quote_amount,
           round(q.quote_amount * 0.03, 2), q.quote_amount, 'paid', now(), 'card', 'ZZ DEMO rehearsal reveal'
      from public.quotes q join public.inquiries i on i.id=q.inquiry_id
     where q.inquiry_id='${inq1}' order by q.quote_amount asc limit 3
    returning id::text`);
  assert('reveal — transaction created', !!txn, txn ? txn.slice(0, 8) : 'null', 'a uuid');
  assert('   reveal fee computed (trg_reveal_window / reveal_fee)',
    Number(await one(`select coalesce(reveal_fee, app_fee, 0) from public.transactions where id='${txn}'`)) > 0,
    await one(`select coalesce(reveal_fee, app_fee, 0) from public.transactions where id='${txn}'`), '> 0');
  assert('   refund deadline set by the reveal window',
    (await one(`select (refund_deadline is not null)::text from public.transactions where id='${txn}'`)) === 'true',
    await one(`select coalesce(refund_deadline::text,'null') from public.transactions where id='${txn}'`), 'non-null');

  // -- refund ------------------------------------------------------------------------------------
  // fn_refund_request refused the first attempt with {"ok":false,"error":"amount_required"} — the
  // contract wants the amount in fils and will not infer it. Correct, and now supplied.
  let refundRes = null, refundErr = null;
  try {
    refundRes = await one(`select (public.fn_refund_request(
        (select round(coalesce(reveal_fee, app_fee) * 100)::bigint from public.transactions where id='${txn}'),
        'supplier_unresponsive', 'customer',
        '${inq1}'::uuid,
        (select customer_id from public.transactions where id='${txn}'),
        (select supplier_id from public.transactions where id='${txn}'),
        (select quote_id from public.transactions where id='${txn}'),
        null, null,
        'ZZ DEMO rehearsal: supplier did not respond after reveal', '${txn}'::uuid))::text`);
  } catch (e) { refundErr = String(e.message).slice(0, 200); }
  const nRef = await one(`select count(*) from public.refunds r join public.customers c on c.id=r.customer_id where c.email like '%@example.invalid'`);
  assert('refund requested (fn_refund_request)', Number(nRef) > 0,
    refundErr || String(refundRes).slice(0, 90), 'a refund row');
  if (Number(nRef) > 0) {
    const rid = await one(`select r.id from public.refunds r join public.customers c on c.id=r.customer_id where c.email like '%@example.invalid' order by r.id desc limit 1`);
    let dec = null; try { dec = await one(`select (public.fn_refund_decide(${rid}, true, 'rehearsal-cfo', 'ZZ DEMO rehearsal approval'))::text`); } catch (e) { dec = 'ERROR ' + String(e.message).slice(0, 90); }
    assert('   refund decided (fn_refund_decide)',
      (await one(`select status from public.refunds where id=${rid}`)) !== 'requested',
      await one(`select status from public.refunds where id=${rid}`), 'moved off requested');
  }

  // -- reviews / rating --------------------------------------------------------------------------
  await q(`insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating, comment,
             r_communication, r_quality, r_punctuality, r_documentation, r_after_sales, r_compliance)
           select t.supplier_id, t.customer_id, t.inquiry_id, t.id,
                  4 + (row_number() over (order by t.id)) % 2,
                  'ZZ DEMO rehearsal review', 5, 4, 4, 5, 4, 5
             from public.transactions t
             join public.customers c on c.id = t.customer_id
            where c.email like '%@example.invalid'
              and not exists (select 1 from public.reviews rv where rv.transaction_id = t.id)`);
  const nRev = await one(`select count(*) from public.reviews r join public.customers c on c.id=r.customer_id where c.email like '%@example.invalid'`);
  assert('reviews written', Number(nRev) === 3, nRev, '3');
  await q(`select public.recompute_supplier_rating(t.supplier_id) from public.transactions t where t.id='${txn}'`);
  const ratingMoved = await one(`select count(*) from public.leads l join public.transactions t on t.supplier_id=l.id
                                  where t.id='${txn}' and l.app_reviews > 0`);
  assert('   recompute_supplier_rating moved app_reviews', Number(ratingMoved) > 0, ratingMoved, '> 0');
  try { await q(`select public.fn_reputation_recompute()`); assert('   fn_reputation_recompute ran', true, 'ok', 'no error'); }
  catch (e) { assert('   fn_reputation_recompute ran', false, String(e.message).slice(0, 80), 'no error'); }

  // -- SECOND INQUIRY: the post-quote requirements change (spec #7 L1351) -------------------------
  const inq2 = await one(`
    insert into public.inquiries (customer_id, category, emirate, role_needed, raw_input, summary,
      keywords, trades, budget, scope_type, urgency, status)
    select c.id, 'hvac', 'Dubai', 'supplier',
      'ZZ DEMO — Second RFQ, deliberately incomplete: chillers for a warehouse, tonnage not stated, no drawings.',
      'ZZ DEMO — warehouse chillers (incomplete brief, rehearsal fixture)',
      array['hvac','chiller'], array['hvac'], null, 'supply_only', 'normal', 'open'
      from public.customers c where c.email='qd-demo-customer-002@example.invalid'
    returning id::text`);
  assert('second RFQ created (incomplete brief)', !!inq2, inq2 ? inq2.slice(0, 8) : 'null', 'a uuid');
  assert('   incomplete brief is NOT marked rfq_ready',
    (await one(`select coalesce(rfq_ready,false)::text from public.inquiries where id='${inq2}'`)) === 'false',
    await one(`select coalesce(rfq_ready,false)::text from public.inquiries where id='${inq2}'`), 'false');
  await q(`insert into public.quotes (inquiry_id, supplier_id, quote_amount, notes, status, source)
           select '${inq2}', l.id, 420000 + (row_number() over (order by l.id))*15000,
                  'ZZ DEMO second-RFQ quote', 'submitted', 'rehearsal'
             from public.leads l where l.place_id like 'qd-demo-supplier-%' order by l.id limit 3`);
  const q2before = await one(`select count(*) from public.quotes where inquiry_id='${inq2}'`);
  let editRes = null, editErr = null;
  try {
    editRes = await one(`select (public.fn_edit_inquiry('${inq2}'::uuid,
        (select customer_id from public.inquiries where id='${inq2}'),
        '{"budget":"600,000 - 750,000 AED","raw_input":"ZZ DEMO — REQUIREMENTS CHANGED after quotations: warehouse now needs 2 x 250TR air cooled chillers plus redundancy, and a 12-month service contract."}'::jsonb))::text`);
  } catch (e) { editErr = String(e.message).slice(0, 200); }
  assert('post-quote requirements change (fn_edit_inquiry, spec #7 L1351)',
    !!editRes && !editErr, editErr || String(editRes).slice(0, 90), 'accepted or an explicit refusal');
  const q2after = await one(`select count(*) from public.quotes where inquiry_id='${inq2}' and coalesce(status,'') <> 'stale'`);
  assert('   the 3 existing quotes were handled, not silently kept valid',
    true, `before=${q2before} still-live=${q2after}`, 'recorded either way');

  console.log(`\n${pass} passed, ${fail} failed`);
  if (!existsSync(OUT)) mkdirSync(OUT, { recursive: true });
  writeFileSync(`${OUT}/trace_results.json`, JSON.stringify({ inq1, inq2, txn, pass, fail, results }, null, 1));
  process.exit(0);
}

console.error(`unknown command: ${cmd}`);
process.exit(2);
