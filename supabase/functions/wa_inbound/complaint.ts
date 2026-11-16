// What WhatsApp registers when its reading says complaint (customer_support, 16 Nov 2026, COO hole H2). No client here, so the
// door's report can be tested: one ticket per message (the Twilio SID, else a hash with no number in it), the number as the
// channel holds it (the SQL links its CONFIRMED owner; no e-mail is looked up from it), Arabic when they wrote Arabic, a reserved
// fixture number as a fixture. prevented by: _shared/complaint_register_scenarios.test.ts
import { hashedKey, type ComplaintReport } from '../_shared/complaint_register.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';

export async function waComplaintReport(o: { from: string; body: string; messageSid?: string | null; receivedAt: string; reading?: string | null;
  name?: string | null; arabic: boolean }): Promise<ComplaintReport> {
  return { channel: 'whatsapp', sourceKey: o.messageSid ? 'whatsapp:' + o.messageSid : await hashedKey('whatsapp', o.from + ':' + o.receivedAt + ':' + o.body.slice(0, 200)),
    message: o.body, reading: String(o.reading ?? '').slice(0, 600) || 'read as a complaint (wa_inbound)', phone: o.from.replace(/^whatsapp:/, ''),
    name: o.name ?? null, lang: o.arabic ? 'ar' : 'en', fixture: isDemoPhone(o.from) };
}
