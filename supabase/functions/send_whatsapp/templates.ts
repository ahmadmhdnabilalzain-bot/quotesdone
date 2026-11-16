// Template keys, template variables and links (split out of index.ts, 9 Nov 2026; a pure move).
import { waInviteTrade } from '../_shared/marketing_send_gate.ts';
import { registrationNeeds } from './registration_reminder.ts';

export function normPhone(p: string){ let s=String(p||'').trim().replace(/[^0-9+]/g,''); if(!s) return ''; if(s.startsWith('00')) s='+'+s.slice(2); if(!s.startsWith('+')){ if(s.startsWith('0')) s='+971'+s.slice(1); else s='+'+s; } return s; }
const SUP_URL='https://quotesdone.com/suppliers';
const APP_URL='https://quotesdone.com/me';
const PORTAL_URL='https://quotesdone.com/portal';
export function tmplKey(type:string):string|null{
  const t=(type||'').toLowerCase();
  if(['new_inquiry','inquiry_matched','supplier_new_inquiry'].includes(t)) return 'supplier_new_inquiry';
  if(['new_quote','quote_received','quote_submitted','quote_ready','quote_available'].includes(t)) return 'customer_new_quote';
  if(['reveal_receipt','reveal','supplier_revealed','supplier_unlocked','reveal_unlocked'].includes(t)) return 'customer_supplier_unlocked';
  // 3 SEP 2026: the supplier's side of the reveal. trg_reveal_receipt queues a WhatsApp to the supplier
  // (type quote_accepted) when they registered a number and opted in — the founder's 19 Aug contract:
  // both parties, both channels. Template registered by wa_template_setup under this key; until its
  // SID lands the row stays queued (see the mapped-but-unregistered branch below), never dropped.
  if(['quote_accepted','supplier_quote_accepted','customer_selected_you'].includes(t)) return 'supplier_quote_accepted';
  // Document compliance: final notice before suspension, and the suspension itself. Both are
  // transactional notices about the supplier's own account, which is why the Twilio template is
  // registered under the UTILITY category rather than MARKETING.
  // 22 Sep 2026: licence_renewal is fn_licence_expiry_sweep's T-30/14/7 ask; its WhatsApp twin is fanned
  // out from the email to the confirmed number and rides the same approved document-expiry template.
  if(['supplier_doc_expiry','doc_final_notice','doc_suspended','doc_expiry','licence_renewal'].includes(t)) return 'supplier_doc_expiry';
  // 14 Sep 2026: the sales engineer's notices about a supplier's own quotes and account (a quote on
  // hold, the regenerated quote to approve, its release, the collaboration warning, the matching hold
  // and its lifting). Transactional, UTILITY category. Until wa_template_setup registers the SID the
  // rows stay queued (mapped-but-unregistered), never dropped; the email twin goes meanwhile.
  if(['quote_spec_hold','quote_spec_regenerated','quote_spec_released','supplier_collaboration_warning','supplier_matching_hold','supplier_matching_hold_lifted'].includes(t)) return 'supplier_account_notice';
  // 23 Sep 2026 (instruction 858): the 3-working-day portfolio reminder is a notice about the supplier's
  // own account too. {{1}} is its subject, {{2}} the portal, which opens on the Services tab.
  if(t==='supplier_portfolio_incomplete') return 'supplier_account_notice';
  // 15 Nov 2026 (sales_engineer): the sales engineer has a question about a quotation the supplier already submitted (the
  // comparison's open points, scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer.sql). A notice about his
  // own quote, like the hold above: {{1}} is its subject, {{2}} the portal, where the conversation holds the points.
  if(t==='quote_comparison_points') return 'supplier_account_notice';
  // 24 Sep 2026 (sales_engineer): the approval notice, twinned from its email to the confirmed number.
  // {{1}} is its subject ("You are verified on QuotesDone: please confirm your categories"), {{2}} the portal.
  if(t==='supplier_approved') return 'supplier_account_notice';
  // 3 Nov 2026 (customer_support): supplier_api save_profile's first-save notice (what the registration still needs, or
  // that it is under review). fn_wa_fanout already queued its twin to the confirmed number and this mapped nothing, so the
  // twin would have been skipped "no WhatsApp template mapping". {{1}} is its subject, {{2}} the portal.
  if(t==='registration_received') return 'supplier_account_notice';
  // 3 Nov 2026 (customer_support): the customer's account-active confirmation (fn_customer_account_active_notice).
  // Its own UTILITY template, English and Arabic; held queued until Meta approves it.
  if(t==='customer_account_active') return 'customer_account_active';
  // 3 Nov 2026 (customer_support): "Your invoice is ready" (the invoice.issued handoff), carrying the QuotesDone invoice
  // reveal_invoice attached. Unmapped until now, so its twin was skipped. Its own UTILITY template, English and Arabic.
  if(t==='invoice_ready') return 'customer_reveal_invoice';
  // 2 Nov 2026 (it_engineer): the registration reminder's WhatsApp twin. Unmapped, the first one (05:00Z) was skipped
  // "no WhatsApp template mapping". Its own UTILITY template, English only; held queued until Meta approves it.
  if(t==='supplier_registration_reminder') return 'supplier_registration_reminder';
  // 6 SEP 2026: the founder's own alert. fn_notify_founder queues it (allowed kind, severe level) and
  // wa_flush drains it here. "QuotesDone alert: {{1}}. Details: {{2}}. Open the OS to act." — registered
  // by wa_template_setup under this key.
  if(t==='founder_alert') return 'founder_alert';
  // 23 Sep 2026: a reasoned answer to the customer's own question, due after their 24-hour window closed
  // (_shared/reasoned_delivery.ts). Held queued until the support_reply template is approved.
  if(t==='support_reply') return 'support_reply';
  // 19 Oct 2026 (marketing, ruling 1184): the WhatsApp supplier invitation, queued only by fn_wa_supplier_invite_queue.
  if(t==='supplier_invite_wa') return 'supplier_invite';
  return null;
}
// 18 SEP 2026: the founder authorised the submission and supplier_account_notice now HAS a template
// (wa_template_setup catalogue, EN + AR, UTILITY). This branch is therefore reached only while Meta
// is still reviewing it, or if its SID were ever unregistered again — so the note no longer says a
// template will never exist, it says the row is waiting for one. The email twin remains the record.
export const AWAITING_TEMPLATE_NOTE = 'awaiting template: the supplier_account_notice WhatsApp template is submitted but not yet registered as an approved SID, so this row stays queued and goes the moment it lands. The email twin carried this notice.';
function shortSummary(s:string){ let x=String(s||'').replace(/\s+/g,' ').trim(); x=x.replace(/^(QuotesDone[:\-\s]*)/i,''); return x.slice(0,90)||'your request'; }
// A template variable may not carry a newline, a tab or a run of spaces (Meta refuses the send), so
// every value is flattened and capped before it reaches Twilio.
function waVar(s:string, max:number){ const x=String(s||'').replace(/\s+/g,' ').trim(); return x.length>max ? x.slice(0,max-1)+'…' : x; }
export function varsFor(key:string, n:{subject?:string|null; body?:string|null; invoice_url?:string|null}): Record<string,string>{
  if (key==='founder_alert') {
    // fn_notify_founder writes 'QuotesDone [level]: event' on the first line and the detail after it.
    const lines = String(n.body||'').split('\n'); const head = lines.shift()||''; const rest = lines.join(' ').trim();
    return {'1': waVar(shortSummary(head||n.subject||'') , 120), '2': waVar(rest || 'see the founder console at quotesdone.com/os', 500)};
  }
  // support_reply: {{1}} their question (the subject), {{2}} the answer (the body), each one line.
  // supplier_invite: {{1}} the trade label (the subject) and nothing else. 27 Oct 2026 (ruling 1301, "safer to not
  // send links"): the template carries no link, so there is no {{2}} and no claim link is read out of the body.
  if (key==='supplier_invite') return {'1': waVar(waInviteTrade(n.subject), 60)};
  if (key==='support_reply') return {'1': waVar(shortSummary(n.subject||''), 120), '2': waVar(String(n.body||''), 700)};
  if (key==='supplier_registration_reminder') return {'1': waVar(registrationNeeds(n.body), 160), '2': linkFor(key)};
  // customer_reveal_invoice: {{1}} the notice's subject, {{2}} the invoice link the loop signed, else the account page.
  if (key==='customer_reveal_invoice') return {'1': shortSummary(n.subject||''), '2': n.invoice_url || linkFor(key)};
  return {'1':shortSummary(n.subject||n.body||''),'2':linkFor(key)};
}
// The page a notice points to. The SMS twin carries the same link as the WhatsApp template.
export function linkFor(key:string|null){
  return key==='supplier_new_inquiry' ? SUP_URL
       : (key==='supplier_doc_expiry' || key==='supplier_quote_accepted' || key==='supplier_account_notice' || key==='supplier_registration_reminder') ? PORTAL_URL
       : APP_URL;
}
