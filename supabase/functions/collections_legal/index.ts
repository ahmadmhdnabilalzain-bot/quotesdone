// collections_legal v1 — non-response fine lifecycle. Sends gentle reminders, and at 30 WORKING days unpaid escalates:
// applies UAE-lawful interest (<=9% p.a., Fed. Decree-Law 50/2022) + a fixed admin fee, then the Legal agent DRAFTS two
// branded PDFs — (1) a formal demand letter to the supplier, (2) the founder's case-support file (with the signed T&C as
// evidence and a moral/reputational-damages head of claim under Art. 293) — backs them up to Dropbox, and raises a founder
// approval card BEFORE the demand letter is sent (oversight). Never auto-sends. inbound_secret gated. Not legal advice.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const BASE = Deno.env.get('SUPABASE_URL')! + '/functions/v1';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
async function sec(k: string){ const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || ''; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
const esc = (s: unknown) => String(s ?? '').replace(/[&<>]/g, (c)=>({'&':'&amp;','<':'&lt;','>':'&gt;'} as any)[c]);
const money = (n: unknown) => 'AED ' + Number(n||0).toLocaleString('en-US',{minimumFractionDigits:2, maximumFractionDigits:2});
const fmtD = (s: unknown) => { if(!s) return '—'; try { return new Date(String(s)).toISOString().slice(0,10); } catch { return String(s); } };
const dbx = (x: unknown) => String(x??'').replace(/[\\/:*?"<>|\r\n\t]+/g,' ').replace(/\s+/g,' ').trim();
const REF = (id: unknown) => 'QD-NR-' + String(id);

async function renderPdf(html: string, title: string, name: string){
  const r = await fetch(`${BASE}/make_pdf`, { method:'POST', headers:{ 'Content-Type':'application/json' }, body: JSON.stringify({ __secret: await sec('cred_fn_to_make_pdf'), html, title, name: name.replace(/[^a-z0-9_]+/gi,'_').slice(0,60), bucket:'supplier-docs', folder:'legal' }) });
  const jd = await r.json().catch(()=>({} as any));
  if (!jd?.path) throw new Error('make_pdf '+(jd?.error||r.status));
  return String(jd.path);
}

function demandHtml(row: any, amt: any, cfg: any){
  const ref = REF(row.due_id);
  return `<html><head><title>Formal Demand for Payment — ${esc(ref)}</title></head><body>
  <h1>Formal Demand for Payment</h1>
  <p><b>Reference:</b> ${esc(ref)} &nbsp; <b>Date:</b> ${fmtD(new Date().toISOString())}</p>
  <p><b>To:</b> ${esc(row.company_name||'Supplier')}${row.contact_name?(' (attn: '+esc(row.contact_name)+')'):''}${row.trade_license_no?(', Trade Licence '+esc(row.trade_license_no)):''}<br>
  <b>From:</b> QuotesDone Technologies, Dubai, UAE (DET E-Trader Licence No. 1633275)</p>
  <p>Dear ${esc(row.company_name||'Partner')},</p>
  <p>This is a formal demand for payment of an outstanding amount owed by you to QuotesDone Technologies under the Supplier Terms &amp; Conditions you accepted on ${fmtD(row.accepted_terms_at)}.</p>
  <h3>Background</h3>
  <p>On ${fmtD(row.reveal_date)}, a customer paid a reveal fee to unlock your company against a request on the QuotesDone platform. You did not respond to that customer within the required period. In accordance with the Terms, the customer's reveal fee was refunded, and a non-response charge equal to that reveal fee became due and payable by you.</p>
  <h3>Amount now due</h3>
  <table style="border-collapse:collapse">
    <tr><td style="padding:3px 14px 3px 0">Non-response charge (principal)</td><td><b>${money(amt.principal)}</b></td></tr>
    <tr><td style="padding:3px 14px 3px 0">Late-payment interest (${(cfg.interest_pa*100)}% p.a. from ${fmtD(row.due_date)}, ${amt.days_overdue} days)</td><td><b>${money(amt.interest)}</b></td></tr>
    <tr><td style="padding:3px 14px 3px 0">Administrative / collection fee</td><td><b>${money(amt.admin_fee)}</b></td></tr>
    <tr><td style="padding:6px 14px 3px 0;border-top:1px solid #999"><b>Total due</b></td><td style="border-top:1px solid #999"><b>${money(amt.total)}</b></td></tr>
  </table>
  <h3>Demand</h3>
  <p>You are required to settle <b>${money(amt.total)}</b> within <b>7 working days</b> of the date of this letter, via the supplier portal or by bank transfer (reply to this notice for details). Your account remains suspended from new matches until the amount is settled.</p>
  <h3>Consequences of non-payment</h3>
  <p>If payment is not received, QuotesDone Technologies reserves all rights to recover this debt through the competent UAE courts, together with interest and costs. We further reserve the right to claim damages arising from your breach, including moral and reputational damages under Article 293 of the UAE Civil Code for harm caused to the platform, its reputation and its users. The Terms &amp; Conditions you signed at registration are relied upon as evidence of this obligation.</p>
  <p>This letter is a formal notice issued without prejudice to our rights.</p>
  <p>Yours faithfully,<br><b>QuotesDone Technologies</b><br>Dubai, United Arab Emirates</p>
  <p style="color:#888;font-size:11px;margin-top:18px">This is a system-generated draft prepared for review and approval before issue.</p>
  </body></html>`;
}
function caseHtml(row: any, amt: any, cfg: any){
  const ref = REF(row.due_id);
  return `<html><head><title>Case Support File — ${esc(ref)}</title></head><body>
  <h1>Case Support File — Unpaid Non-Response Charge</h1>
  <p><b>Reference:</b> ${esc(ref)} &nbsp; <b>Prepared:</b> ${fmtD(new Date().toISOString())}</p>
  <h3>Parties</h3>
  <p><b>Claimant:</b> QuotesDone Technologies, Dubai, UAE (DET E-Trader Licence No. 1633275).<br>
  <b>Respondent:</b> ${esc(row.company_name||'Supplier')}${row.trade_license_no?(', Trade Licence '+esc(row.trade_license_no)):''}${row.emirate?(', '+esc(row.emirate)):''}. Contact: ${esc(row.contact_name||'—')}, ${esc(row.email||'—')}, ${esc(row.phone||'—')}.</p>
  <h3>Governing contract</h3>
  <p>Supplier Terms &amp; Conditions accepted by the Respondent on ${fmtD(row.accepted_terms_at)}. The signed acceptance is on file and attached as <b>Evidence A</b>.</p>
  <h3>Facts</h3>
  <p>On ${fmtD(row.reveal_date)} a customer paid to reveal the Respondent against a platform request. The Respondent failed to respond within the required period. The customer's reveal fee was refunded by the Claimant, and under the Terms a non-response charge equal to that reveal fee became payable by the Respondent. Payment fell due on ${fmtD(row.due_date)} and remains unpaid after more than ${cfg.escalate_working_days} working days despite reminders.</p>
  <h3>Amounts claimed</h3>
  <table style="border-collapse:collapse">
    <tr><td style="padding:3px 14px 3px 0">Principal (non-response charge)</td><td><b>${money(amt.principal)}</b></td></tr>
    <tr><td style="padding:3px 14px 3px 0">Contractual late-payment interest (${(cfg.interest_pa*100)}% p.a., Fed. Decree-Law No. 50/2022)</td><td><b>${money(amt.interest)}</b></td></tr>
    <tr><td style="padding:3px 14px 3px 0">Administrative / collection cost</td><td><b>${money(amt.admin_fee)}</b></td></tr>
    <tr><td style="padding:6px 14px 3px 0;border-top:1px solid #999"><b>Sub-total (liquidated)</b></td><td style="border-top:1px solid #999"><b>${money(amt.total)}</b></td></tr>
  </table>
  <h3>Heads of claim</h3>
  <ol>
    <li>The debt (principal) plus contractual late-payment interest and reasonable collection costs.</li>
    <li>Moral / reputational damages under Article 293 of the UAE Civil Code for harm to the Claimant's reputation, standing and user trust caused by the Respondent's breach — <i>to be assessed by the Court</i> (a specific sum is not pre-fixed, as the Court determines moral damages on the evidence).</li>
  </ol>
  <h3>Evidence bundle</h3>
  <ul>
    <li><b>A.</b> Respondent's signed Supplier Terms &amp; Conditions (accepted ${fmtD(row.accepted_terms_at)}).</li>
    <li><b>B.</b> Reveal / transaction record and the customer refund record.</li>
    <li><b>C.</b> Reminder notifications and the formal demand letter (Ref ${esc(ref)}).</li>
  </ul>
  <p style="color:#888;font-size:11px;margin-top:18px">Prepared by the QuotesDone Legal agent for the founder to instruct a UAE-licensed lawyer. This is not a court filing and not legal advice; figures are subject to assessment by the Court (Art. 390/340 UAE Civil Code).</p>
  </body></html>`;
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(()=>({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'collections_legal');
    if (!__auth.ok) return J({ error:'forbidden' }, 403);
    const { data: cfg } = await admin.from('collections_config').select('*').eq('id',1).maybeSingle();
    const C = cfg || { interest_pa:0.09, admin_fee:250, escalate_working_days:30, reminder_max:3 };
    const owner = (await sec('admin_emails')||'').split(/[,;\s]+/).filter(Boolean)[0] || 'management@quotesdone.com';

    // ---- 1) gentle reminders (pre-escalation) ----
    let reminded = 0;
    const { data: rem } = await admin.from('supplier_dues').select('id,supplier_id,amount_due,status,reminders,last_reminder_at,legal_stage')
      .in('status',['due','pending','reminded']).is('legal_stage', null).lt('reminders', C.reminder_max);
    for (const d of (rem||[])){
      if (d.last_reminder_at && (Date.now() - new Date(d.last_reminder_at).getTime()) < 4*864e5) continue;
      const { data: l } = await admin.from('leads').select('company_name,claimed_by,email').eq('id', d.supplier_id).maybeSingle();
      await admin.from('notifications').insert({ type:'nonresponse_reminder', to_email: l?.claimed_by||l?.email, to_role:'supplier', channel:'portal', status:'portal', lead_id: d.supplier_id,
        subject:'Reminder: outstanding non-response charge',
        body:'Reminder: a non-response charge of '+money(d.amount_due)+' is outstanding on your account (the reveal fee refunded to a customer after a paid reveal was not responded to). Please settle it on the portal to lift the hold on new matches. QuotesDone charges no commission on won jobs.' });
      await admin.from('supplier_dues').update({ status:'reminded', reminders:(d.reminders||0)+1, last_reminder_at:new Date().toISOString() }).eq('id', d.id);
      reminded++;
    }

    // ---- 2) escalate at >= escalate_working_days ----
    const { data: due } = await admin.rpc('fn_dues_to_escalate', { p_days: C.escalate_working_days });
    let escalated = 0; const results: any[] = [];
    for (const row of (due||[])){
      try {
        const principal = Number(row.principal||0);
        const interest = Math.round(principal * Number(C.interest_pa) * (Number(row.days_overdue)/365) * 100)/100;
        const admin_fee = Number(C.admin_fee);
        const total = Math.round((principal + interest + admin_fee)*100)/100;
        const amt = { principal, interest, admin_fee, total, days_overdue: row.days_overdue };
        const ref = REF(row.due_id);
        const demandPath = await renderPdf(demandHtml(row, amt, C), 'Formal Demand '+ref, 'demand_'+row.due_id);
        const casePath = await renderPdf(caseHtml(row, amt, C), 'Case File '+ref, 'casefile_'+row.due_id);
        await admin.from('supplier_dues').update({ status:'legal', legal_stage:'legal', legal_escalated_at:new Date().toISOString(),
          interest_amount:interest, admin_fee, total_claim:total, demand_letter_path:demandPath, case_file_path:casePath, evidence_terms_path: row.signed_terms_path||null,
          fine_pct: Number(C.interest_pa)*100, fine_amount: 0 /* C1 fix (OS audit): interest lives only in interest_amount. supplier_pay.owed() and fn_gl_sync_business sum interest_amount + fine_amount, so mirroring interest here double-billed the supplier and double-credited the GL. */ }).eq('id', row.due_id);
        // keep the account held
        await admin.from('leads').update({ matching_blocked:true, matching_block_reason:'Unpaid non-response charge — in legal collections' }).eq('id', row.supplier_id);
        // back up both PDFs to the supplier's Dropbox Legal folder
        const base = '/QuotesDone Backup/Suppliers/'+dbx(row.category)+'/'+dbx(row.company_name||('Supplier '+row.supplier_id))+' ('+row.supplier_id+')/Legal/';
        for (const [p, label, kind] of [[demandPath,'Formal Demand Letter '+ref+'.pdf','demand'],[casePath,'Case Support File '+ref+'.pdf','case']] as any){
          await admin.from('doc_backups').insert({ entity:'supplier', entity_id:String(row.supplier_id), doc_type:'Legal '+kind, bucket:'supplier-docs', path:p, file_name:label, dropbox_path: base+label, source:'storage', dedupe_key:'LEGAL:'+row.due_id+':'+kind });
        }
        // founder approval card (approve BEFORE the demand letter is sent)
        await admin.from('agent_actions').insert({ agent:'legal_ai', kind:'dues_legal_demand', status:'pending', risk:'high',
          title:'Approve demand letter — '+(row.company_name||('Supplier '+row.supplier_id))+' ('+money(total)+')',
          recommendation:'A supplier is '+row.days_overdue+' days overdue on a non-response charge. A formal demand letter and a case-support file have been drafted. Approve to issue the demand letter to the supplier; the case file is for your records / to instruct a lawyer.',
          detail: JSON.stringify({ ref, supplier_id:row.supplier_id, company:row.company_name, principal, interest, admin_fee, total, demand_letter_path:demandPath, case_file_path:casePath, signed_terms:row.signed_terms_path }),
          target_table:'supplier_dues', target_id:String(row.due_id) });
        // alert founder
        await admin.from('notifications').insert({ type:'legal_pack_ready', to_email:owner, to_role:'admin', channel:'email',
          subject:'Legal pack ready for approval — '+(row.company_name||'supplier')+' '+money(total),
          body:(row.company_name||'A supplier')+' is '+row.days_overdue+' days overdue on a non-response charge of '+money(principal)+'. Total now '+money(total)+' (incl. '+(C.interest_pa*100)+'% p.a. interest '+money(interest)+' + admin '+money(admin_fee)+'). A demand letter and your case-support file are drafted and saved; approve in the OS to issue the demand letter.' });
        escalated++; results.push({ due:row.due_id, total, demandPath, casePath });
      } catch (e){ results.push({ due:row.due_id, error:String((e as Error)?.message||e).slice(0,160) }); }
    }
    return J({ ok:true, reminded, escalated, results });
  } catch (e){ return J({ error:String((e as Error)?.message||e) }, 500); }
});
