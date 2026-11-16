// deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. supabase/functions/wa_inbound/optin_code.test.ts
//
// A SUPPLIER CONFIRMS THE NUMBER FOR JOB REQUESTS ON WHATSAPP BY SENDING, FROM IT, THE CODE OUR E-MAIL GAVE HIM; AND A REPLY TO THE
// CONSENT QUESTION IS READ BY A MODEL (16 Nov 2026, marketing, agent L2_OPTIN, ledger 1184/1373). Before: a yes on WhatsApp was a
// keyword rule (fn_wa_is_affirmative) that refused "yes put me on WhatsApp" and an Arabic yes; no path confirmed an e-mailed yes.
import { assert, assertEquals } from 'jsr:@std/assert@1';
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const { optinSituation } = await import('./optin_code.ts');
const { consentReadBy } = await import('./arrival.ts');

const AR_YES = 'نعم، أرسلوها على الواتساب';
const Q = 'May QuotesDone send you WhatsApp messages about requests for quotation in your trade? Reply YES to agree, or STOP if you do not want them.';

/** A stand-in for the one read consentReadBy makes: the open ask on this number, or none. */
function db(question: string | null) {
  const seen: Record<string, unknown> = {};
  const q = {
    select: () => q, eq: (k: string, v: unknown) => { seen[k] = v; return q; }, is: () => q, gte: () => q, order: () => q, limit: () => q,
    maybeSingle: async () => ({ data: question ? { question } : null, error: null }),
  };
  return { seen, client: { from: (t: string) => { seen.table = t; return q; } } as never };
}
// the stub model: it reads the reply and answers; code only passes its verdict on
const model = async (_sys: string, input: string) => JSON.stringify({ agrees: /yes put me on WhatsApp|نعم/.test(input.slice(input.indexOf('HIS REPLY:'))), quote: '' });

Deno.test('a reply to the consent question is read by the model: an English and an Arabic yes are consent, a question is not', async () => {
  const d = db(Q);
  assertEquals(await consentReadBy('whatsapp:+971500000771', 'yes put me on WhatsApp', { ask: model, db: d.client }), 'the consent reader');
  assertEquals([d.seen.table, d.seen.phone], ['supplier_whatsapp_consent_ask', '+971500000771'], 'only the ask on this number is read');
  assertEquals(await consentReadBy('+971500000771', AR_YES, { ask: model, db: db(Q).client }), 'the consent reader');
  assertEquals(await consentReadBy('+971500000771', 'who is this?', { ask: model, db: db(Q).client }), null);
  // nobody asked this number: no model call, no consent, whatever the words
  let called = false;
  assertEquals(await consentReadBy('+971500000771', 'yes put me on WhatsApp', { ask: async () => { called = true; return '{"agrees":true}'; }, db: db(null).client }), null);
  assertEquals(called, false);
  // the model is down: nothing is recorded
  assertEquals(await consentReadBy('+971500000771', 'yes', { ask: async () => null, db: db(Q).client }), null);
});

Deno.test('the confirmation reply is the model\'s, from the routine\'s answer; anything that is not an opt-in code goes to the ordinary turn', () => {
  assertEquals(optinSituation({ ok: false, code: 'no_pending_code' }), null);
  assertEquals(optinSituation({ ok: false, code: 'no_code' }), null);
  assertEquals(optinSituation(null), null);
  assert(optinSituation({ ok: true, company_name: 'ZZ DEMO Tiling' })!.includes('ZZ DEMO Tiling') && optinSituation({ ok: true })!.includes('STOP'));
  assert(optinSituation({ ok: false, code: 'too_many_tries' })!.includes('too many wrong codes'));
  assert(optinSituation({ ok: false, code: 'number_belongs_to_another' })!.includes('another account'));
});

Deno.test('the step runs after the number is identified, never for a customer, and answers through the model', async () => {
  const src = await Deno.readTextFile(new URL('./optin_code.ts', import.meta.url));
  assert(/if \(audience === 'customer'\) return undefined;/.test(src));
  assert(/const out = await sayFor\('supplier'\)\(situation, 'en'\);/.test(src));
  assert(/fn_supplier_whatsapp_optin_confirm/.test(src));
  const index = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(index.indexOf('await identify(t);') < index.indexOf('await optinCode(t)'));
  assert(index.indexOf('await memberPhone(t)') < index.indexOf('await optinCode(t)'));
  const arrival = await Deno.readTextFile(new URL('./arrival.ts', import.meta.url));
  assert(/rpc\('fn_supplier_whatsapp_consent_read', \{ p_from: From, p_read_by: readBy \}\)/.test(arrival), 'the model that read the yes is put on the ask');
  assert(arrival.indexOf("fn_supplier_whatsapp_consent_read") < arrival.indexOf("rpc('fn_marketing_files_wa_invite_reply'"), 'before the reply is filed');
});
