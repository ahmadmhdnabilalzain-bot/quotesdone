// WHAT A CUSTOMER READS ON THEIR CARD STATEMENT FOR A REVEAL FEE (13 Oct 2026, agent: accountant).
//
// Measured 13 Oct 2026 (GET /v1/account, live and test keys, read only): the account's shortened
// descriptor (settings.card_payments.statement_descriptor_prefix) is "QUOTESDONE" and the full one
// (settings.payments.statement_descriptor) is "QUOTESDONE.COM". A card charge prints
// "<prefix>* <suffix>", and Stripe caps that whole line at 22 characters, so the suffix has
// 22 - 10 - 2 = 10 characters. "QUOTESDONE" is already printed, so the suffix carries what the charge
// was for and which job: "REVEAL 104" when it fits, else "RV <job>", e.g. QUOTESDONE* RV 1042.
// Stripe refuses < > \ ' " * in a descriptor; only A-Z, 0-9 and spaces are kept.
// A recognisable statement line is the cheapest dispute prevention there is ("I don't recognise this").
export const DESCRIPTOR_PREFIX = 'QUOTESDONE';
export const SUFFIX_MAX = 22 - DESCRIPTOR_PREFIX.length - 2;

export function revealDescriptorSuffix(jobNo: string): string {
  const job = String(jobNo || '').toUpperCase().replace(/^QD-/, '').replace(/[^A-Z0-9]/g, '');
  for (const s of ['REVEAL ' + job, 'REVEAL' + job, 'RV ' + job]) if (s.length <= SUFFIX_MAX) return s.trim();
  return ('RV' + job).slice(0, SUFFIX_MAX);
}
