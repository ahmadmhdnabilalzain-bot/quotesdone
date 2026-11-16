// RETIRED 18 September 2026 — it_engineer. A rehearsal is retired WITH its subject, and every one of this
// file's five loops has lost its subject. It is kept, not deleted, because the sanctions screen it
// rehearses is still LIVE and still wanted; restoring this file is the cheapest way to prove it the day
// the defect in §3 below is fixed. Measured against htdblwldjkcgjvmqkbeh on 18 Sep 2026:
//
//   1. THE FILE HAD BEEN DEAD FOR ELEVEN DAYS. Its twelfth line calls fn_supplier_invite_followups, and
//      that routine — with fn_supplier_lead_intake and fn_supplier_lead_sourcing, loops (1) to (4) — was
//      DROPPED FROM PRODUCTION ON 7 SEPTEMBER 2026 with everything that did not belong to the new
//      structure (the removal note is in scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql).
//      Running the file printed: "function public.fn_supplier_invite_followups(unknown) does not exist".
//      Its last assertion also read fn_phase_d_fixture_residue(), removed with the phase programme and
//      recorded in scripts/sql/DROPPED.txt line 601. Nothing in the repository invokes this file.
//
//   2. THE SEED WAS ALSO WRONG, AND IS FIXED BELOW. Both fixture suppliers were written
//      approval_status='approved', verified=true with none of the founder's mandatory six, which
//      trg_leads_e0_mandatory_six_gate (live since #698, 15 Sep 2026) refuses outright. They now carry the
//      evidence — a verified +9715 mobile, owner_email_verified, a licence and a company profile that
//      storage.objects actually HOLDS, and signed terms — and the probe asserts its own completeness
//      before it measures anything. That half is proven: with the seed fixed, the gate accepted both rows
//      and fn_supplier_sanctions_screen ran and matched them. The gate is the founder's rule and was never
//      touched. scripts/checks/a_seeded_approved_supplier_carries_the_mandatory_six.test.mjs now keeps
//      every seeding surface in the estate honest about this.
//
//   3. AND THEN THE LIVE ROUTINE ITSELF FAILED — a finding for whoever owns supplier compliance, not a
//      fixture defect, and the reason this file is retired rather than merely trimmed:
//
//        ERROR: 23503: insert or update on table "org_tasks" violates foreign key constraint
//        "org_tasks_assigned_agent_fkey". Key (assigned_agent)=(compliance_mgr) is not present in
//        table "org_agents".
//
//      public.fn_supplier_sanctions_screen opens its compliance task on 'compliance_mgr' and its outreach
//      hold on 'bd'. public.org_agents holds exactly five seats — accountant, ceo, customer_support,
//      it_engineer, sales_engineer — so NEITHER EXISTS. The screen therefore throws on the first real hit
//      it ever finds and writes nothing: a guard that names a remedy that does not exist. It has never
//      been noticed because the screen has never matched anybody. Deciding which seat owns a sanctions
//      hit is the founder's call and applying the fix is a production change, so it is recorded here and
//      reported rather than guessed at.
//
// Nothing below was softened to make anything green. The file is left exactly as it would run.
//
// ---------------------------------------------------------------------------------------------------
// THE SANCTIONS SCREEN ON A REGISTERED SUPPLIER — the sandbox rehearsal (6 Sep 2026; cut back 18 Sep 2026).
//
// Proves on the production database, inside ONE aborted transaction that commits nothing, that
//   (1) the screen matches a ZZ DEMO supplier against fixture list entries (legal name exact, owner
//       token overlap), opens ONE compliance task carrying the evidence and ONE hold on outreach, and
//       leaves a clean ZZ DEMO supplier alone,
//   (2) fn_supplier_screening_decide records a FALSE POSITIVE without touching the lead,
//   (3) and a CONFIRMED hit moves the supplier through the existing ban path (banned, matching_blocked,
//       approval withdrawn) and closes both tasks,
//   (4) and that no real lead, task or hit was touched: the whole-table counts are read before and after.
// Everything happens in one `do` block that ends with `raise exception 'PROBE|…'`, so the fixtures, the
// hits and the tasks all roll back; the rehearsal window rows are the only committed writes and they are
// closed at the end.
//
// WHAT WAS CUT, AND WHY (measured 18 Sep 2026). This file used to rehearse five loops. Three of them —
// the invitation follow-ups, the inbox intake and the lead sourcing — call fn_supplier_invite_followups,
// fn_supplier_lead_intake and fn_supplier_lead_sourcing, and ALL THREE WERE DROPPED FROM PRODUCTION ON
// 7 SEPTEMBER 2026 with everything that did not belong to the new structure (see the removal note in
// scripts/sql/the_bd_manager_runs_the_supplier_acquisition_loop.sql). The file therefore died on its
// twelfth line with "function public.fn_supplier_invite_followups(unknown) does not exist" and had done
// so for eleven days without anyone running it; the sixth assertion also read
// fn_phase_d_fixture_residue(), removed with the phase programme and recorded in scripts/sql/DROPPED.txt.
// A rehearsal is retired WITH its subject, never resuscitated by rebuilding a retired loop, and never
// softened to green. What survives is the sanctions screen, which is live and is rehearsed here in full.
//
// THE MANDATORY SIX ARE EVIDENCE, NOT COLUMN VALUES. The two fixture suppliers below are `approved` —
// they must be, because fn_supplier_screening_decide withdraws an approval only from a row that HAS one
// (`case when approval_status = 'approved' then 'rejected'`), and that withdrawal is the property this
// rehearsal exists to prove. Since #698 trg_leads_e0_mandatory_six_gate refuses an approval unless all
// six are present as evidence: reg_mobile is owner_phone_verified plus a +9715 mobile, reg_email is
// owner_email_verified (never leads.email), reg_licence and reg_profile require storage.objects to
// actually HOLD the document, reg_terms reads signed_terms_path. The gate is the founder's rule and is
// never softened; the seed is what changes. Committed demo suppliers elsewhere in the estate are built by
// scripts/archive/staging/demo_factory.mjs — this file cannot call it, because the factory commits rows and
// uploads real PDFs through the storage API while this probe must leave the database byte-for-byte as it
// found it, inside one transaction that always aborts.
//
//   node scripts/archive/staging/rehearse_supplier_loops.mjs
import { sql } from '../../lib/db.mjs';

const tag = 'zzdemo-loops-' + Math.random().toString(36).slice(2, 8);
const checks = [];
const ok = (name, pass, detail) => { checks.push(pass); console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(62)} ${detail}`); };
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
// The two fixture documents. Paths under zz-demo/, so a real supplier's document is never named, and the
// storage rows are inserted inside the probe and roll back with it.
const LIC = `zz-demo/${tag}-licence.pdf`;
const PROF = `zz-demo/${tag}-profile.pdf`;

const before = (await sql(`select
  (select count(*) from public.leads) leads,
  (select count(*) from public.org_tasks) tasks,
  (select count(*) from public.screening_entry) entries,
  (select count(*) from public.supplier_screening_hit) hits,
  (select count(*) from storage.objects where bucket_id = 'supplier-docs') docs`))[0];

await sql(`insert into public.rehearsal_window (run_tag, opened_by, note) values (${q('qd_run:' + tag)}, 'rehearse_supplier_loops', 'aborted-transaction probe of the supplier sanctions screen')`);
let msg = '';
try {
  try {
    await sql(`do $p$
declare
  v_sc jsonb; v_d1 jsonb; v_d2 jsonb;
  l_san bigint; l_clean bigint; run_id bigint; h_name bigint; h_owner bigint;
  n_hits int; hits_real int; n_ctask int; n_bdhold int; six text[];
  b_banned boolean; b_banned_fp boolean; b_blocked boolean; a_status text; t_c text; t_b text;
begin
  set local statement_timeout = '30s';

  -- the two documents the six count only when storage actually holds them. on conflict: two runs at once
  -- would otherwise serialize on the unique index (bucket_id, name) until the first one rolled back.
  insert into storage.objects (bucket_id, name) values ('supplier-docs', ${q(LIC)}), ('supplier-docs', ${q(PROF)})
  on conflict (bucket_id, name) do nothing;

  -- fixtures: one supplier whose legal name and owner are on the fixture list, one that is clean.
  -- ZZ DEMO — in the name and @example.invalid in the address are what fn_supplier_sanctions_screen reads
  -- to know these are the rehearsal's own rows, and what makes leads.is_demo true.
  insert into public.leads (company_name, email, source, signatory_name, contact_name, phone,
                            owner_phone_verified, owner_email_verified, license_doc_path,
                            company_profile_doc_path, signed_terms_path, approval_status, verified, accepted_terms_at)
  values ('ZZ DEMO — Sanctioned Trading LLC', 'sanctioned@example.invalid', 'canary',
          'Abd Al-Rahman Bin Umayr Al-Nuaymi', 'ZZ DEMO — Owner', '+971500000092', true, true,
          ${q(LIC)}, ${q(PROF)}, 'suppliers/zz-demo-' || ${q(tag)} || '-sanctioned.pdf', 'approved', true, now())
  returning id into l_san;
  insert into public.leads (company_name, email, source, signatory_name, phone,
                            owner_phone_verified, owner_email_verified, license_doc_path,
                            company_profile_doc_path, signed_terms_path, approval_status, verified, accepted_terms_at)
  values ('ZZ DEMO — Clean Supplier LLC', 'clean@example.invalid', 'canary', 'Fatima ZZ DEMO', '+971500000093',
          true, true, ${q(LIC)}, ${q(PROF)}, 'suppliers/zz-demo-' || ${q(tag)} || '-clean.pdf', 'approved', true, now())
  returning id into l_clean;

  -- The gate would already have refused both inserts; this states the seed's own completeness, so a future
  -- change to the definition of the six is named here rather than read as a screening result.
  six := public.fn_supplier_mandatory_six_for(l_san) || public.fn_supplier_mandatory_six_for(l_clean);
  if cardinality(six) <> 0 then
    raise exception 'PROBE|{"seed_refused": "the ZZ DEMO suppliers are not complete, so nothing below measures the screen. Missing: %"}', array_to_string(six, ', ');
  end if;

  insert into public.screening_run (source, source_url, sha256, entries, status, note, run_tag)
  values ('un_consolidated', 'fixture', 'zz-fixture', 3, 'ok', 'ZZ DEMO — fixture list', ${q(tag)}) returning id into run_id;
  insert into public.screening_entry (run_id, source, entry_type, reference, name) values
    (run_id, 'un_consolidated', 'entity', 'ZZ-E.001', 'ZZ DEMO — SANCTIONED TRADING L.L.C.'),
    (run_id, 'un_consolidated', 'individual', 'ZZ-I.001', 'ABD AL-RAHMAN BIN UMAYR AL-NUAYMI'),
    (run_id, 'un_consolidated', 'individual', 'ZZ-I.002', 'ZZ DEMO — Unrelated Person');

  v_sc := public.fn_supplier_sanctions_screen(array[run_id], ${q(tag)});
  select count(*) into n_hits from public.supplier_screening_hit where lead_id = l_san and status = 'open';
  select count(*) into hits_real from public.supplier_screening_hit where lead_id not in (l_san, l_clean);
  select id into h_name from public.supplier_screening_hit where lead_id = l_san and field = 'legal_name' limit 1;
  select id into h_owner from public.supplier_screening_hit where lead_id = l_san and field = 'owner' limit 1;
  select count(*) into n_ctask from public.org_tasks where assigned_agent = 'compliance_mgr' and dept_key = 'legal' and title like 'Sanctions screening hit: ZZ DEMO — Sanctioned%' and status = 'assigned';
  select count(*) into n_bdhold from public.org_tasks where assigned_agent = 'bd' and title like 'Hold outreach and onboarding: ZZ DEMO — Sanctioned%' and status = 'assigned';

  -- decide: the owner hit is a false positive first (lead untouched), then the name hit is confirmed (ban path)
  v_d1 := public.fn_supplier_screening_decide(h_owner, 'false_positive', 'compliance_mgr');
  select coalesce(banned, false) into b_banned_fp from public.leads where id = l_san;
  v_d2 := public.fn_supplier_screening_decide(h_name, 'confirmed', 'compliance_mgr');
  select coalesce(banned, false), coalesce(matching_blocked, false), approval_status into b_banned, b_blocked, a_status from public.leads where id = l_san;
  select status into t_c from public.org_tasks where assigned_agent = 'compliance_mgr' and title like 'Sanctions screening hit: ZZ DEMO — Sanctioned%' order by id desc limit 1;
  select status into t_b from public.org_tasks where assigned_agent = 'bd' and title like 'Hold outreach and onboarding: ZZ DEMO — Sanctioned%' order by id desc limit 1;

  raise exception 'PROBE|%', jsonb_build_object(
    'screen', v_sc, 'san_open_hits', n_hits, 'hits_on_real_leads', hits_real,
    'compliance_tasks', n_ctask, 'bd_holds', n_bdhold,
    'decide_fp', v_d1, 'banned_after_fp', b_banned_fp, 'decide_confirm', v_d2,
    'banned', b_banned, 'blocked', b_blocked, 'approval', a_status, 'ctask', t_c, 'btask', t_b)::text;
end $p$;`);
    msg = 'NO_EXCEPTION';
  } catch (e) {
    const m = String(e.message || e); const i = m.indexOf('PROBE|'); msg = i >= 0 ? m.slice(i + 6) : m;
  }
} finally {
  await sql(`update public.rehearsal_window set ended_at = now() where run_tag = ${q('qd_run:' + tag)} and ended_at is null`);
}
if (msg === 'NO_EXCEPTION' || !msg.startsWith('{')) { console.log('probe did not return its counts:', msg.slice(0, 600)); process.exit(1); }
// the probe's jsonb is the first balanced {...} in the error text (the API may append context lines)
const extract = (t) => { const st = t.indexOf('{'); let d = 0, inS = false; for (let i = st; i < t.length; i++) { const c = t[i]; if (inS) { if (c === '\\') i++; else if (c === '"') inS = false; continue; } if (c === '"') inS = true; else if (c === '{') d++; else if (c === '}') { d--; if (d === 0) return t.slice(st, i + 1); } } return t.slice(st); };
const r = JSON.parse(extract(msg.replace(/\\"/g, '"')));
// A REFUSED SEED IS NOT A SCREENING RESULT. Without this, an incomplete seed would arrive as absent keys
// and every assertion below would read "the screen found nothing" — an instrument measuring the wrong
// subject. Fix the seed (it must satisfy the founder's mandatory six); never the gate.
if (r.seed_refused) { console.log(`THE PROBE COULD NOT SEED A VERIFIABLE DEMO SUPPLIER, so this rehearsal asserts NOTHING about the screen. ${r.seed_refused}`); process.exit(1); }

ok('screen: 2 hits on the sanctioned fixture (legal name exact + owner), 0 on the clean one, 0 on real leads', r.san_open_hits === 2 && r.hits_on_real_leads === 0 && r.screen.suppliers === 2, `open=${r.san_open_hits} real=${r.hits_on_real_leads} ${JSON.stringify(r.screen)}`);
ok('one compliance task with evidence + one BD hold opened', r.compliance_tasks === 1 && r.bd_holds === 1, `compliance=${r.compliance_tasks} bd=${r.bd_holds}`);
ok('false positive decided: lead untouched, one hit still open', r.decide_fp.ok === true && r.decide_fp.open_hits_left === 1 && r.banned_after_fp === false, `banned_after_fp=${r.banned_after_fp} ${JSON.stringify(r.decide_fp)}`);
ok('confirmed: existing ban path (banned, matching_blocked, approval withdrawn) and both tasks closed', r.decide_confirm.ok === true && r.banned === true && r.blocked === true && r.approval === 'rejected' && r.ctask === 'done' && r.btask === 'done', `banned=${r.banned} blocked=${r.blocked} approval=${r.approval} ctask=${r.ctask} btask=${r.btask} ${JSON.stringify(r.decide_confirm)}`);

const after = (await sql(`select
  (select count(*) from public.leads) leads,
  (select count(*) from public.org_tasks) tasks,
  (select count(*) from public.screening_entry) entries,
  (select count(*) from public.supplier_screening_hit) hits,
  (select count(*) from storage.objects where bucket_id = 'supplier-docs') docs`))[0];
const same = ['leads', 'tasks', 'entries', 'hits', 'docs'].every((k) => String(before[k]) === String(after[k]));
ok('everything rolled back: leads, tasks, entries, hits and supplier-docs objects all identical', same,
   `leads ${before.leads}->${after.leads} tasks ${before.tasks}->${after.tasks} entries ${before.entries}->${after.entries} hits ${before.hits}->${after.hits} docs ${before.docs}->${after.docs}`);

const pass = checks.filter(Boolean).length;
console.log(`\nREHEARSAL ${pass}/${checks.length} PASS (${tag}); nothing committed except the closed rehearsal_window row.`);
process.exit(pass === checks.length ? 0 : 1);
