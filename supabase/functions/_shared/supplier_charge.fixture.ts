// supplier_charge.fixture.ts — one ZZ DEMO non-response case, end to end, for the recovery documents.
// Nothing here is a real company, person, payment or Stripe object: names carry "ZZ DEMO", addresses
// end in example.invalid, Stripe ids carry ZZDEMO, and the licence number is not a DET number.
import { revealChargeFor } from './reveal_fee.ts';
import type { CaseFile } from './supplier_charge_documents.ts';

const QUOTE_VALUE = 78_900;
const paidFor = revealChargeFor(QUOTE_VALUE, 0.03, 'domestic');

export const DEMO_CASE: CaseFile = {
  case_ref: 'QD-NR-ZZD3M0AA',
  supplier: {
    legal_name: 'ZZ DEMO — Gulf Breeze HVAC Contracting L.L.C.',
    legal_name_ar: 'ZZ DEMO — جلف بريز لمقاولات التكييف ذ.م.م',
    licence_no: 'ZZ-DEMO-000000',
    licence_authority: 'Department of Economy and Tourism — Dubai',
    licence_authority_ar: 'دائرة الاقتصاد والسياحة — دبي',
    address: 'Office ZZ-01, Demo Building, Al Quoz Industrial Area 3, Dubai, UAE',
    address_ar: 'مكتب ZZ-01، مبنى تجريبي، القوز الصناعية 3، دبي، الإمارات العربية المتحدة',
    email: 'accounts@gulfbreeze-zzdemo.example.invalid',
    mobile: '+971 50 000 0000',
    signatory: 'ZZ DEMO Manager',
  },
  acceptance: {
    version: 'v10', accepted_at: '2026-09-15T09:12:44Z', ip: '192.0.2.10',
    sha256: 'cdafedd34ced86b0a764bdd1c72d4441b0ce8e4dd37a228c6fcb1f79f8435ee8',
  },
  inquiry: { id: 'zzd3m0aa-7c1e-4f00-9a00-000000000001', summary: 'Supply and install ducted split AC, 3-bedroom villa, Al Barsha', summary_ar: 'توريد وتركيب مكيف سبليت مخفي بمجاري هواء لفيلا 3 غرف نوم في البرشاء' },
  quote_value: QUOTE_VALUE,
  reveal: { paid_at: '2026-10-01T10:05:00Z', payment_intent: 'pi_ZZDEMO0000000000000001', reveal_fee: paidFor.base_fee, processing_fee: paidFor.processing_fee },
  ladder: {
    chase_day3_at: '2026-10-06T09:00:00Z', final_call_day5_at: '2026-10-08T11:30:00Z',
    chase_delivery: 'delivered (email + WhatsApp), message ids ZZDEMO-OUTBOX-101 / ZZDEMO-WA-101',
    chase_delivery_ar: 'سُلِّمت (البريد الإلكتروني وواتساب)، معرّفا الرسالتين ZZDEMO-OUTBOX-101 / ZZDEMO-WA-101',
    final_call_outcome: 'no answer; voicemail and WhatsApp left, message id ZZDEMO-WA-102',
    final_call_outcome_ar: 'لم يُجب؛ تُركت رسالة صوتية ورسالة واتساب، معرّف الرسالة ZZDEMO-WA-102',
  },
  refund: { refunded_at: '2026-10-09T08:00:00Z', refund_id: 're_ZZDEMO0000000000000001', reveal_fee: paidFor.base_fee, processing_fee: paidFor.processing_fee },
  invoice: { number: 'QD-INV-NR-2026-0001', date: '2026-10-09' },
  reminders: [{ n: 1, date: '2026-10-20' }, { n: 2, date: '2026-11-03' }],
  final_demand: { date: '2026-11-17', service: 'email to the registered address (ZZDEMO-OUTBOX-301, delivered), WhatsApp to the registered mobile (ZZDEMO-WA-301, delivered) and the supplier portal', service_ar: 'البريد الإلكتروني المسجّل (ZZDEMO-OUTBOX-301، سُلِّم) وواتساب على الهاتف المسجّل (ZZDEMO-WA-301، سُلِّم) وبوابة المورّد' },
  as_of: '2026-11-17',
};
