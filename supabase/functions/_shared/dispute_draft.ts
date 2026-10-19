// SAVE EVERY WAITING DISPUTE'S EVIDENCE AT STRIPE AS A DRAFT (13 Oct 2026, agent: accountant).
//
// Moved out of accountant/index.ts so stripe_webhook can run it the moment charge.dispute.created
// arrives, instead of waiting for the hourly duty. The hourly duty still runs it as the backstop.
// submit=false always: submitting is final, and fn_accountant_dispute_drafted files the CEO's review
// item (scripts/sql/the_accountant_answers_every_card_dispute_before_stripe_closes_it.sql, section 2b).
// Evidence: fn_accountant_dispute_evidence; the invoice PDF goes up as evidence[receipt] and the
// customer's signed-terms certificate as evidence[customer_signature].
import { disputeEvidenceForm } from './dispute_evidence.ts';
import { timedFetch } from './timed_fetch.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
type StoredFile = { bucket?: string; path?: string; name?: string } | null | undefined;

async function upload(admin: Admin, key: string, f: StoredFile): Promise<string | undefined> {
  if (!f?.path) return undefined;
  const { data: blob } = await admin.storage.from(String(f.bucket)).download(String(f.path));
  if (!blob) return undefined;
  const fd = new FormData();
  fd.set('purpose', 'dispute_evidence');
  fd.set('file', blob, String(f.name || 'evidence.pdf'));
  const fr = await timedFetch('https://files.stripe.com/v1/files', { method: 'POST', headers: { Authorization: 'Bearer ' + key }, body: fd }, 30_000);
  const fj = await fr.json().catch(() => ({}));
  return fr.ok && fj?.id ? String(fj.id) : undefined;
}

export async function draftDisputes(admin: Admin, keys: { live?: string | null; test?: string | null }, only?: string) {
  const out: Record<string, unknown>[] = [];
  const { data: toDraft } = await admin.rpc('fn_accountant_disputes_to_draft');
  // deno-lint-ignore no-explicit-any
  for (const ev of (toDraft || []) as Record<string, any>[]) {
    if (ev?.ok !== true || (only && ev.dispute !== only)) continue;
    const key = ev.livemode ? keys.live : keys.test;
    if (!key) {
      await admin.rpc('fn_accountant_dispute_drafted', { p_id: ev.dispute, p_ok: false, p_response: null, p_error: 'no Stripe key for this mode' });
      continue;
    }
    const receipt = await upload(admin, key, ev.receipt);
    const signature = await upload(admin, key, ev.terms_certificate);
    const r = await fetch('https://api.stripe.com/v1/disputes/' + encodeURIComponent(String(ev.dispute)), {
      method: 'POST', headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: disputeEvidenceForm(ev.fields || {}, { receipt, customer_signature: signature }, false).toString(),   // a DRAFT: submit=false
    });
    const j = await r.json().catch(() => ({}));
    await admin.rpc('fn_accountant_dispute_drafted', {
      p_id: ev.dispute, p_ok: r.ok,
      p_response: r.ok ? { id: j.id, status: j.status, receipt_file: receipt ?? null, signature_file: signature ?? null, draft: true } : null,
      p_error: r.ok ? null : 'HTTP ' + r.status + ': ' + String(j?.error?.message || '').slice(0, 300),
    });
    out.push({ dispute: ev.dispute, drafted: r.ok, receipt_file: receipt ?? null, signature_file: signature ?? null });
  }
  return out;
}
