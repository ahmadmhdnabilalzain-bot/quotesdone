// THE FORM STRIPE TAKES FOR A DISPUTE'S EVIDENCE (14 Sep 2026, agent: accountant, duty 7).
//
// fn_accountant_dispute_evidence (scripts/sql/the_accountant_answers_every_card_dispute_before_stripe_closes_it.sql)
// assembles the text from the records; this turns it into the POST /v1/disputes/{id} body. Only Stripe's
// own text fields are passed, each within Stripe's length, so a field the database adds later can never
// be sent by accident. Pure, so it is tested alone (dispute_evidence.test.ts).
export const DISPUTE_TEXT_FIELDS = ['access_activity_log', 'billing_address', 'cancellation_policy_disclosure',
  'cancellation_rebuttal', 'customer_email_address', 'customer_name', 'customer_purchase_ip', 'duplicate_charge_explanation',
  'product_description', 'refund_policy_disclosure', 'refund_refusal_explanation', 'service_date', 'uncategorized_text'] as const;
// Stripe caps the combined text of a dispute's evidence at 150,000 characters; each field is kept well inside it.
export const MAX_FIELD_CHARS = 20000;

export function disputeEvidenceForm(fields: Record<string, unknown>, files: { receipt?: string } = {}, submit = true): URLSearchParams {
  const f = new URLSearchParams();
  for (const k of DISPUTE_TEXT_FIELDS) {
    const v = fields?.[k];
    if (v === null || v === undefined || String(v).trim() === '') continue;
    f.set(`evidence[${k}]`, String(v).slice(0, MAX_FIELD_CHARS));
  }
  if (files.receipt && /^file_/.test(files.receipt)) f.set('evidence[receipt]', files.receipt);
  f.set('submit', submit ? 'true' : 'false');
  f.set('metadata[answered_by]', 'accountant');
  return f;
}
