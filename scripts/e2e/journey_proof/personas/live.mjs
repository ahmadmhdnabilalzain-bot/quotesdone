// scripts/e2e/journey_proof/personas/live.mjs — what run.mjs needs to play a journey with PEOPLE on the live site. Seat:
// customer_support. Pure wiring: every network call goes through the functions run.mjs hands in (fixtures.mjs call/read,
// portal_raster.mjs rasterise), the same doors the harness already uses for its fixtures. Nothing here runs by itself.
//
//   personaScenario(base, persona)   a journey (scenarios.mjs, e.g. A) with the persona's own job and words: the run's
//                                    machinery (sign-up, demo suppliers, matching, reveal) is the base journey's
//   playerFor({ ... })               the persona player with the live model (ai_gateway, the run's tag) or the stub (--dry)
//   liveSupplierDoors({ ... })       supplier_api as the portal calls it, with the supplier's own session:
//                                    message -> review_start + review_message (the quotation chat), the answer read back
//                                    upload  -> extract_quote (the file read) + submit_quote (what he would submit)
//                                    afterSilence -> the notifications the platform composed to him during the run
//   supplierIdentity(sp, fx, file)   what identifies a supplier persona, for the reverse anonymity check
import { createPlayer, stubComplete, gatewayComplete } from './player.mjs';

export function personaScenario(base, persona) {
  if (persona.job.trade !== base.trade) throw new Error(`REFUSED: persona ${persona.key} is a ${persona.job.trade} job; journey ${base.key} makes ${base.trade} suppliers`);
  return { ...base, folder: `${base.folder}_persona_${persona.key}`, label: `${base.label} ${persona.key.replace(/_/g, ' ')}`, short: `${persona.short} (a persona, not a script)`,
    title: persona.job.title, how_made: `${persona.label}, ${persona.short}, typed in his own words: a model played him from a hidden truth sheet, answering only what was asked`,
    opener: persona.opener, facts: [], confirm: null, attach: [], voice: null, defaultLines: persona.job.lines, persona,
    // journey A of 15 Nov 2026 (tag 8288bec3) spent USD 0.7371 in 75 calls (ai_cost_log, SELECT), 0.7088 of it in 34 inquiry_intake calls;
    // the person's own calls add about USD 0.0002 each (json_extraction, measured), so the base cap holds
    estimate_usd: Math.max(base.estimate_usd || 0, 0.75) };
}

/** The persona player for a live run: the model through ai_gateway under the run tag (capped), or the stub with --dry. */
export function playerFor({ persona, dry, base, service, fnSecret, e2eSecret, runTag, email, maxCalls = 30, capUsd = 0.05 }) {
  const complete = dry ? stubComplete(persona) : gatewayComplete({ base, service, fnSecret, e2eSecret, runTag, subject: email ? { email } : null });
  return createPlayer({ persona, complete, maxCalls, capUsd });
}

const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));
const lit = (v) => `'${String(v).replace(/'/g, "''")}'`;
export function liveSupplierDoors({ call, read, rasterise, fx, quotable, since, sleep = sleepMs }) {
  const sup = (body, ms = 240000) => call('supplier_api', fx.jwt, body, ms);
  const settle = async (r) => { let v = r; for (let i = 0; i < 40 && (v.json?.reviewing || v.json?.state === 'reviewing'); i++) { await sleep(6000); v = await sup({ action: 'review_thread', inquiry_id: quotable }); } return v; };
  const engineer = (v) => (v.json?.messages || []).filter((m) => m.role === 'sales_engineer');
  return {
    message: async (text) => {
      const s = await sup({ action: 'review_start', inquiry_id: quotable }, 180000);
      const before = engineer(s).length;
      const v = await settle(await sup({ action: 'review_message', inquiry_id: quotable, text }));
      const said = engineer(v).slice(before).map((m) => m.body_en || m.body || '').filter(Boolean).join(' ');
      return { http: v.status, said: said || null, state: v.json?.state ?? null };
    },
    upload: async ({ b64, filename, mime, bytes, typed = {} }) => {
      const images = mime === 'application/pdf' ? (await rasterise(bytes)).map(({ mime: m, data }) => ({ mime: m, data })) : [{ mime, data: b64 }];
      const ex = await sup({ action: 'extract_quote', inquiry_id: quotable, images, original: { b64, filename, mime } });
      const pr = ex.json?.proposal || {};
      const readAmount = pr.amount ?? null; const amount = Number(readAmount ?? typed.total);
      // QuoteForm.buildPayload: the reading, with each field it left blank typed by the supplier himself
      const body = { action: 'submit_quote', inquiry_id: quotable, amount, currency: 'AED', lead_time: pr.lead_time || typed.lead_time, notes: [pr.notes, typed.notes].filter(Boolean).join(' '),
        scope: pr.scope || pr.description_anonymized || '', conditions: pr.conditions || '', exclusions: pr.exclusions || '', validity: pr.validity || typed.validity, payment_terms: pr.payment_terms || typed.payment_terms,
        warranty: pr.warranty || typed.warranty, items: pr.line_items || [], masked_terms: pr.masked_terms || null, source: 'upload', original_file_path: ex.json?.original_file_path, original_file_name: ex.json?.original_file_name,
        subtotal: pr.subtotal ?? undefined, vat_amount: pr.vat_amount ?? undefined, trn: pr.trn ?? undefined, vat_treatment: 'exclusive', price_ex_vat: Number(pr.subtotal ?? amount) };
      const s = await sup(body);
      const qid = s.json?.quote?.id ?? s.json?.quote_id ?? (s.json?.options || [])[0]?.quote_id ?? null;
      return { http: s.status, extract_http: ex.status, read_amount: readAmount, typed_by_supplier: readAmount == null, quote_id: qid, accepted: s.json?.accepted ?? null, held: s.json?.held ?? null,
        code: s.json?.code ?? (ex.json?.ok === false ? ex.json?.code ?? 'not_read' : null), missing: (s.json?.missing || s.json?.spec_missing || []).map((m) => m?.attr ?? m) };
    },
    afterSilence: async () => (await read(`select created_at at, channel, coalesce(subject, kind, type, '') what, status from public.notifications where lead_id = ${Number(fx.leadId)} and created_at >= ${lit(since)} order by created_at`))
      .map((r) => ({ at: r.at, what: `${r.channel || 'message'} "${String(r.what).slice(0, 80)}" (${r.status})` })),
  };
}

/** What identifies a supplier persona (his card and his demo fixture), for the reverse anonymity check of step 5. */
export function supplierIdentity(sp, fx, fileName) {
  return [
    { label: "the supplier's letterhead name", value: sp.letterhead, kind: 'name' },
    { label: "the supplier's mobile on his quotation", value: sp.phone, kind: 'phone' },
    { label: "the supplier's e-mail on his quotation", value: sp.email, kind: 'email' },
    { label: "the supplier's TRN", value: sp.trn, kind: 'text' },
    { label: "the supplier's registered mobile", value: fx?.phone, kind: 'phone' },
    { label: "the supplier's login e-mail", value: fx?.email, kind: 'email' },
    ...(fileName ? [{ label: "his quotation's file name", value: fileName, kind: 'text' }] : []),
  ].filter((x) => x.value);
}
