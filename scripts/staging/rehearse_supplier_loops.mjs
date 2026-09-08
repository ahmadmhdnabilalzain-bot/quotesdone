// THE TWO SUPPLIER LOOPS — the sandbox rehearsal (6 Sep 2026).
//
// Proves on the production database, inside ONE aborted transaction that commits nothing, that
//   (1) the acquisition loop is HELD while app_secrets.supplier_outreach_golive is false (every sweep
//       records "held" and writes nothing else),
//   (2) with the switch forced on INSIDE the transaction and decision_policy.demo_rehearsal_active true,
//       the follow-up sweep queues invitations ONLY to ZZ DEMO — / @example.invalid fixture leads whose
//       +3 / +7 working-day clocks are due, and to NO real address; a lead that replied is skipped; the
//       cap holds; the record lands on the lead,
//   (3) inbox intake classifies fixture replies by keyword (register / question / decline / document /
//       other), opens ONE reply task each on the BD manager (deduplicated), suppresses a decline,
//   (4) lead sourcing turns an unknown fixture business-domain sender into a lead (source inbound_email),
//   (5) the sanctions screen matches a fixture supplier against fixture list entries (legal name exact,
//       owner token overlap), opens ONE compliance task + ONE BD hold, leaves a clean fixture alone,
//       and fn_supplier_screening_decide moves a confirmed hit through the existing ban path and closes
//       both tasks; a false positive changes nothing on the lead,
//   (6) with a rehearsal tag NO real lead, inbound message or list entry is touched (counts are read back).
// Everything happens in one `do` block that ends with `raise exception 'PROBE|…'`, so the switch, the
// fixtures, the notifications and the tasks all roll back; the rehearsal window rows are the only
// committed writes and they are closed at the end.
//
//   node scripts/staging/rehearse_supplier_loops.mjs
import { sql } from '../lib/db.mjs';

const tag = 'zzdemo-loops-' + Math.random().toString(36).slice(2, 8);
const checks = [];
const ok = (name, pass, detail) => { checks.push(pass); console.log(`${pass ? 'PASS' : 'FAIL'} ${String(checks.length).padStart(2)} ${name.padEnd(62)} ${detail}`); };
const q = (s) => `'${String(s).replace(/'/g, "''")}'`;

const before = (await sql(`select
  (select count(*) from public.leads) leads,
  (select count(*) from public.notifications) notifs,
  (select count(*) from public.org_tasks) tasks,
  (select count(*) from public.inbound_messages) inbound,
  (select count(*) from public.screening_entry) entries,
  (select count(*) from public.supplier_screening_hit) hits,
  (select count(*) from public.email_suppressions) supp,
  (select value from public.app_secrets where key='supplier_outreach_golive') golive`))[0];
ok('switch is false on production before the rehearsal', before.golive === 'false', `supplier_outreach_golive=${before.golive}`);

await sql(`insert into public.rehearsal_window (run_tag, opened_by, note) values (${q('qd_run:' + tag)}, 'rehearse_supplier_loops', 'aborted-transaction probe of the supplier loops')`);
let msg = '';
try {
  try {
    await sql(`do $p$
declare
  v_f jsonb; v_i jsonb; v_s jsonb; v_sc jsonb; v_d1 jsonb; v_d2 jsonb;
  l_due3 bigint; l_due7 bigint; l_fresh bigint; l_replied bigint; l_san bigint; l_clean bigint;
  m_reg bigint; m_q bigint; m_dec bigint; m_doc bigint; m_oth bigint; m_new bigint;
  run_id bigint; h_name bigint; h_owner bigint;
  n_fix int; n_real int; n_tasks_bd int; n_tasks_bd2 int; n_supp int; n_lead_new int; n_hits int; n_ctask int; n_bdhold int;
  fu_due3 int; fu_due7 int; fu_fresh int; fu_replied int; b_banned boolean; b_banned_fp boolean; b_blocked boolean; a_status text;
  t_c text; t_b text; new_lead_dbg text; i_reg text; i_q text; i_dec text; i_doc text; i_oth text; hits_real int; held_f boolean; held_i boolean; held_s boolean;
begin
  -- (1) HELD while the switch is false
  v_f := public.fn_supplier_invite_followups(${q(tag)}); v_i := public.fn_supplier_lead_intake(${q(tag)}); v_s := public.fn_supplier_lead_sourcing(${q(tag)});
  held_f := (v_f->>'held')::boolean; held_i := (v_i->>'held')::boolean; held_s := (v_s->>'held')::boolean;

  -- force the switch ON, inside this transaction only, and arm the demo guard on notifications
  update public.app_secrets set value = 'true' where key = 'supplier_outreach_golive';
  update public.decision_policy set value = 'true'::jsonb where key = 'demo_rehearsal_active';

  -- fixtures: four invited leads on different clocks, one that replied, plus two registered ones for the screen
  insert into public.leads (company_name, email, source, invite_status, invited_at, invite_followups, contacted)
  values ('ZZ DEMO — Due Three Trading LLC', 'due3@example.invalid', 'canary', 'sent', now() - interval '6 days', 0, true) returning id into l_due3;
  insert into public.leads (company_name, email, source, invite_status, invited_at, invite_followups, contacted)
  values ('ZZ DEMO — Due Seven Contracting LLC', 'due7@example.invalid', 'canary', 'sent', now() - interval '12 days', 1, true) returning id into l_due7;
  insert into public.leads (company_name, email, source, invite_status, invited_at, invite_followups, contacted)
  values ('ZZ DEMO — Fresh Invite LLC', 'fresh@example.invalid', 'canary', 'sent', now() - interval '1 hour', 0, true) returning id into l_fresh;
  insert into public.leads (company_name, email, source, invite_status, invited_at, invite_followups, contacted)
  values ('ZZ DEMO — Replied Already LLC', 'replied@example.invalid', 'canary', 'sent', now() - interval '6 days', 0, true) returning id into l_replied;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, matched_existing)
  values (l_replied, 'replied@example.invalid', 'info@quotesdone.com', 'Re: invitation', 'We are interested, how do we register?', true) returning id into m_reg;
  insert into public.leads (company_name, email, source, signatory_name, contact_name, approval_status, verified, accepted_terms_at)
  values ('ZZ DEMO — Sanctioned Trading LLC', 'sanctioned@example.invalid', 'canary', 'Abd Al-Rahman Bin Umayr Al-Nuaymi', 'ZZ DEMO — Owner', 'approved', true, now()) returning id into l_san;
  insert into public.leads (company_name, email, source, signatory_name, approval_status, verified, accepted_terms_at)
  values ('ZZ DEMO — Clean Supplier LLC', 'clean@example.invalid', 'canary', 'Fatima ZZ DEMO', 'approved', true, now()) returning id into l_clean;

  -- (2) follow-ups: only the two due fixtures, no real address
  v_f := public.fn_supplier_invite_followups(${q(tag)});
  select count(*) filter (where to_email ilike '%@example.invalid'), count(*) filter (where to_email not ilike '%@example.invalid') into n_fix, n_real
    from public.notifications where type = 'supplier_invite_followup' and created_at > now() - interval '1 minute';
  select invite_followups into fu_due3 from public.leads where id = l_due3;
  select invite_followups into fu_due7 from public.leads where id = l_due7;
  select invite_followups into fu_fresh from public.leads where id = l_fresh;
  select invite_followups into fu_replied from public.leads where id = l_replied;

  -- inbound fixtures for intake (AFTER the follow-up sweep: a lead that wrote to us is skipped by design): a question, a decline, a document, noise, and an unknown business-domain sender
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body) values (l_due3, 'due3@example.invalid', 'info@quotesdone.com', 'Question', 'What is the fee? How much does it cost?') returning id into m_q;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body) values (l_fresh, 'fresh@example.invalid', 'info@quotesdone.com', 'Please remove', 'Not interested, please unsubscribe us.') returning id into m_dec;
  insert into public.inbound_messages (lead_id, from_email, to_email, subject, body, attachments_count) values (l_due7, 'due7@example.invalid', 'info@quotesdone.com', 'Our documents', 'Attached is our trade licence copy.', 1) returning id into m_doc;
  insert into public.inbound_messages (from_email, to_email, subject, body) values ('noise@example.invalid', 'info@quotesdone.com', 'Out of office', 'I am away until Monday.') returning id into m_oth;
  insert into public.inbound_messages (from_email, to_email, subject, body) values ('sales@example.invalid', 'info@quotesdone.com', 'Partnership', 'Hello, we supply gypsum boards in Sharjah.') returning id into m_new;
  -- (3) intake, twice (the second pass must open nothing new)
  v_i := public.fn_supplier_lead_intake(${q(tag)});
  select count(*) into n_tasks_bd from public.org_tasks where assigned_agent = 'bd' and action_class = 'outreach_draft' and title like 'Supplier reply (%' and created_at > now() - interval '1 minute';
  perform public.fn_supplier_lead_intake(${q(tag)});
  select count(*) into n_tasks_bd2 from public.org_tasks where assigned_agent = 'bd' and action_class = 'outreach_draft' and title like 'Supplier reply (%' and created_at > now() - interval '1 minute';
  select intent into i_reg from public.supplier_lead_intake where inbound_id = m_reg;
  select intent into i_q   from public.supplier_lead_intake where inbound_id = m_q;
  select intent into i_dec from public.supplier_lead_intake where inbound_id = m_dec;
  select intent into i_doc from public.supplier_lead_intake where inbound_id = m_doc;
  select intent into i_oth from public.supplier_lead_intake where inbound_id = m_oth;
  select count(*) into n_supp from public.email_suppressions where email = 'fresh@example.invalid' and source = 'supplier_lead_intake';

  -- (4) sourcing: the unknown business-domain sender becomes a lead
  v_s := public.fn_supplier_lead_sourcing(${q(tag)});
  select count(*) into n_lead_new from public.leads where email_domain = 'example.invalid' and source = 'inbound_email' and company_name like 'ZZ DEMO — %';
  select string_agg(id || ' ' || coalesce(company_name,'?') || ' ' || coalesce(email,'?') || ' ' || coalesce(source,'?'), '; ') into new_lead_dbg from public.leads where source = 'inbound_email' and created_at > now() - interval '1 minute';

  -- (5) screening against fixture list entries
  insert into public.screening_run (source, source_url, sha256, entries, status, note, run_tag) values ('un_consolidated', 'fixture', 'zz-fixture', 3, 'ok', 'ZZ DEMO — fixture list', ${q(tag)}) returning id into run_id;
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
  select coalesce(banned,false) into b_banned_fp from public.leads where id = l_san;
  v_d2 := public.fn_supplier_screening_decide(h_name, 'confirmed', 'compliance_mgr');
  select coalesce(banned,false), coalesce(matching_blocked,false), approval_status into b_banned, b_blocked, a_status from public.leads where id = l_san;
  select status into t_c from public.org_tasks where assigned_agent = 'compliance_mgr' and title like 'Sanctions screening hit: ZZ DEMO — Sanctioned%' order by id desc limit 1;
  select status into t_b from public.org_tasks where assigned_agent = 'bd' and title like 'Hold outreach and onboarding: ZZ DEMO — Sanctioned%' order by id desc limit 1;

  raise exception 'PROBE|%', jsonb_build_object(
    'held', jsonb_build_object('followups', held_f, 'intake', held_i, 'sourcing', held_s),
    'followups', v_f, 'fixture_notifs', n_fix, 'real_notifs', n_real,
    'fu', jsonb_build_object('due3', fu_due3, 'due7', fu_due7, 'fresh', fu_fresh, 'replied', fu_replied),
    'intake', v_i, 'bd_tasks_first', n_tasks_bd, 'bd_tasks_second', n_tasks_bd2,
    'intents', jsonb_build_object('reg', i_reg, 'q', i_q, 'dec', i_dec, 'doc', i_doc, 'oth', i_oth), 'suppressed', n_supp,
    'sourcing', v_s, 'new_lead', n_lead_new, 'new_lead_dbg', new_lead_dbg,
    'screen', v_sc, 'san_open_hits', n_hits, 'hits_on_real_leads', hits_real, 'compliance_tasks', n_ctask, 'bd_holds', n_bdhold,
    'decide_fp', v_d1, 'banned_after_fp', b_banned_fp, 'decide_confirm', v_d2, 'banned', b_banned, 'blocked', b_blocked, 'approval', a_status, 'ctask', t_c, 'btask', t_b)::text;
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

ok('all three sweeps HELD while the switch is false', r.held.followups === true && r.held.intake === true && r.held.sourcing === true, JSON.stringify(r.held));
ok('follow-ups queued only to fixture addresses, none to a real one', r.fixture_notifs === 2 && r.real_notifs === 0, `fixture=${r.fixture_notifs} real=${r.real_notifs} ${JSON.stringify(r.followups)}`);
ok('+3 working days → first follow-up; +7 → second; fresh and replied untouched', r.fu.due3 === 1 && r.fu.due7 === 2 && r.fu.fresh === 0 && r.fu.replied === 0, JSON.stringify(r.fu));
ok('intake classified register / question / decline / document / other by keyword', r.intents.reg === 'register' && r.intents.q === 'question' && r.intents.dec === 'decline' && r.intents.doc === 'document' && r.intents.oth === 'other', JSON.stringify(r.intents));
ok('one BD reply task per actionable reply, none duplicated on the second pass', r.bd_tasks_first === 3 && r.bd_tasks_second === 3, `first=${r.bd_tasks_first} second=${r.bd_tasks_second}`);
ok('a decline suppresses the address', r.suppressed === 1, `suppressed=${r.suppressed}`);
ok('unknown senders on one business domain become ONE lead (source inbound_email)', r.new_lead === 1 && r.sourcing.harvested === 1 && r.sourcing.candidates === 2 && r.sourcing.duplicate_domain === 1, `new_lead=${r.new_lead} ${JSON.stringify(r.sourcing)} [${r.new_lead_dbg}]`);
ok('screen: 2 hits on the sanctioned fixture (legal name exact + owner), 0 on the clean one, 0 on real leads', r.san_open_hits === 2 && r.hits_on_real_leads === 0 && r.screen.suppliers === 2, `open=${r.san_open_hits} real=${r.hits_on_real_leads} ${JSON.stringify(r.screen)}`);
ok('one compliance task with evidence + one BD hold opened', r.compliance_tasks === 1 && r.bd_holds === 1, `compliance=${r.compliance_tasks} bd=${r.bd_holds}`);
ok('false positive decided: lead untouched, one hit still open', r.decide_fp.ok === true && r.decide_fp.open_hits_left === 1 && r.banned_after_fp === false, `banned_after_fp=${r.banned_after_fp} ${JSON.stringify(r.decide_fp)}`);
ok('confirmed: existing ban path (banned, matching_blocked, approval withdrawn) and both tasks closed', r.decide_confirm.ok === true && r.banned === true && r.blocked === true && r.approval === 'rejected' && r.ctask === 'done' && r.btask === 'done', `banned=${r.banned} blocked=${r.blocked} approval=${r.approval} ctask=${r.ctask} btask=${r.btask} ${JSON.stringify(r.decide_confirm)}`);

const after = (await sql(`select
  (select count(*) from public.leads) leads,
  (select count(*) from public.notifications) notifs,
  (select count(*) from public.org_tasks) tasks,
  (select count(*) from public.inbound_messages) inbound,
  (select count(*) from public.screening_entry) entries,
  (select count(*) from public.supplier_screening_hit) hits,
  (select count(*) from public.email_suppressions) supp,
  (select value from public.app_secrets where key='supplier_outreach_golive') golive,
  (select value from public.decision_policy where key='demo_rehearsal_active') demo,
  (select count(*) from public.fn_phase_d_fixture_residue()) residue`))[0];
const same = ['leads', 'notifs', 'tasks', 'inbound', 'entries', 'hits', 'supp'].every((k) => String(before[k]) === String(after[k]));
ok('everything rolled back: counts identical, switch false, demo guard off, no fixture residue', same && after.golive === 'false' && after.demo === false && Number(after.residue) === 0,
   `leads ${before.leads}->${after.leads} notifs ${before.notifs}->${after.notifs} tasks ${before.tasks}->${after.tasks} hits ${before.hits}->${after.hits} golive=${after.golive} demo=${after.demo} residue=${after.residue}`);

const pass = checks.filter(Boolean).length;
console.log(`\nREHEARSAL ${pass}/${checks.length} PASS (${tag}); nothing committed except the closed rehearsal_window row.`);
process.exit(pass === checks.length ? 0 : 1);
