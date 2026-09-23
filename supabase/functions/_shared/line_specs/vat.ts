// line_specs/vat.ts — the price the customer compares and pays 3% on is the price EXCLUDING VAT.
//
// The founder, 14 Sep 2026: "for suppliers quotations, we definetely hide the vat details when
// sharing the quotes with the customer". QuotesDone is not VAT-registered. So the supplier's VAT
// treatment, VAT amount and TRN are captured for the record (quotes.vat_treatment / vat_amount /
// supplier_trn, never served to a customer), and quotes.price_ex_vat is the one figure that is
// compared and that the reveal fee is taken on. A price whose ex-VAT value cannot be determined
// exactly is a missing detail: the quote is held and the supplier is asked to state it.
//
// Deterministic, in this order: the supplier's own ex-VAT figure from the portal; a stated subtotal plus a VAT
// amount; the TREATMENT the supplier stated — chosen on the portal's VAT select, or reasoned from their words by
// think() (_shared/reasoned_intake.ts vatBasis, decision point line_specs.options_derive_vat) — with the VAT amount
// (or a stated rate, as a number) for an inclusive price. Anything else — including silence, or a reasoning still
// held under the model hold — is not stated, never assumed. The text is read for the TRN only (an identity-number
// FORMAT); what it says about VAT is never matched here (23 Sep 2026, founder_instruction 886-903).
import { findTrn } from '../identity_numbers.ts';

export type VatTreatment = 'exclusive' | 'inclusive' | 'not_registered' | 'not_stated' | 'confirmed_on_portal';
export type VatRead = { treatment: VatTreatment; price_ex_vat: number | null; vat_amount: number | null; vat_rate: number | null; trn: string | null };

const r2 = (n: number) => Math.round(n * 100) / 100;

export function readVat(i: { amount: number | null; subtotal?: number | null; vat_amount?: number | null; text?: string | null; stated?: string | null; price_ex_vat?: number | null; vat_rate?: number | null }): VatRead {
  const trn = findTrn(String(i.text ?? ''));
  const rate = Number(i.vat_rate) > 0 && Number(i.vat_rate) < 100 ? Number(i.vat_rate) : null;
  const amt = Number(i.amount) > 0 ? Number(i.amount) : null;
  const vat = Number(i.vat_amount) > 0 ? Number(i.vat_amount) : null;
  const sub = Number(i.subtotal) > 0 ? Number(i.subtotal) : null;
  const base = { vat_amount: vat, vat_rate: rate, trn };
  if (Number(i.price_ex_vat) > 0) return { treatment: 'confirmed_on_portal', price_ex_vat: r2(Number(i.price_ex_vat)), ...base };
  if (i.stated === 'not_registered') return { treatment: 'not_registered', price_ex_vat: amt, ...base, vat_amount: null };
  if (sub && vat) return { treatment: 'exclusive', price_ex_vat: sub, ...base };
  if (i.stated === 'exclusive') return { treatment: 'exclusive', price_ex_vat: amt, ...base };
  if (i.stated === 'inclusive') {
    if (amt && vat && vat < amt) return { treatment: 'inclusive', price_ex_vat: r2(amt - vat), ...base };
    if (amt && rate && rate > 0 && rate < 100) return { treatment: 'inclusive', price_ex_vat: r2(amt / (1 + rate / 100)), ...base };
    return { treatment: 'inclusive', price_ex_vat: null, ...base };
  }
  return { treatment: 'not_stated', price_ex_vat: null, ...base };
}
