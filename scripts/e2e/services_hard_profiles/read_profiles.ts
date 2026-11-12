// THE STAGE OF run.mjs: the REAL reader on the hard-profile set, the way registration runs it after an upload
// (supplier_docs_later -> supplier_doc_trades). sales_engineer, 12 Nov 2026; ruling 1647; docs/reports/2026-11-12-supplier-service-profiling.md.
//   1. code reads each uploaded file into text      readDocForTrades(..., { textOnly: true })   (the PDF text layer, pages, licence activities)
//   2. the model reads all the documents together   readTogether([profile, licence], deps, company)  (through the deployed ai_gateway)
//   3. the proposal as it would be stored           withReading + servicesAndLicence (source_docs.docs / proposed_services / licence_check)
// The production modules of THIS checkout are imported, never copied. Without --model nothing is asked and nothing is spent.
// Run it through run.mjs, which opens the tagged window, makes the ZZ DEMO subject that carries the spend, and tears it down:
//   deno run -A --unsafe-proto --no-lock --node-modules-dir=none read_profiles.ts <profiles dir> <out.json> [--model] [--repeats 2] [--only H01,H02]
const S = new URL('../../../supabase/functions/_shared/', import.meta.url).href;
const { readDocForTrades, readTogether, withReading, servicesAndLicence, preparedText } = await import(S + 'supplier_doc_trades.ts');
const { modelParts } = await import(S + 'supplier_trade_choice.ts');
const [dir, outPath] = Deno.args;
const flag = (f: string) => Deno.args.includes(f);
const val = (f: string) => { const i = Deno.args.indexOf(f); return i >= 0 ? Deno.args[i + 1] : null; };
const MODEL = flag('--model'), REPEATS = Number(val('--repeats') || 1), ONLY = val('--only')?.split(',') ?? null;
const keys = JSON.parse(await Deno.readTextFile(`${dir}/answer_keys.json`)).profiles as { id: string; company: string; profile: string; licence: string }[];

// deno-lint-ignore no-explicit-any
let deps: any = {}, catalogue: any = null;
const calls: { step: string; text: string; content: string; ms: number }[] = [];
if (MODEL) {
  const { createClient } = await import('jsr:@supabase/supabase-js@2');
  const { liveProfileReader, readTaxonomy } = await import(S + 'supplier_profile_reading.ts');
  const TAG = Deno.env.get('QD_RUN_TAG')!, SUBJECT = JSON.parse(Deno.env.get('QD_SUBJECT') || 'null');
  if (!/^[a-z0-9]{4,16}$/.test(TAG || '') || !SUBJECT) { console.error('--model needs QD_RUN_TAG and QD_SUBJECT (the driver opens the window)'); Deno.exit(2); }
  const headers = { Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': Deno.env.get('QD_E2E_SECRET') || '' };
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  // reader @5, every answer recorded for the offline test (the one-call chooser of @4 that the analysis measured is deleted)
  deps = { readProfile: liveProfileReader(admin, { subject: SUBJECT, headers, onAnswer: (step: string, text: string, content: string, ms: number) => calls.push({ step, text, content, ms }) }) };
  catalogue = await readTaxonomy(admin);
}
// deno-lint-ignore no-explicit-any
const out: any[] = [];
for (const k of keys) {
  if (ONLY && !ONLY.includes(k.id)) continue;
  const bytes = async (f: string) => new Uint8Array(await Deno.readFile(`${dir}/${f}`));
  const doc = async (f: string, kind: 'profile' | 'licence') => await readDocForTrades({ path: `zz-demo-hard/${k.id}/${f}`, name: f, kind, bytes: await bytes(f), mime: /\.docx$/.test(f) ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' : 'application/pdf', names: [k.company] }, {}, { textOnly: true });
  const prof = await doc(k.profile, 'profile'), lic = await doc(k.licence, 'licence');
  const given = [prof, lic].filter((d) => d.status === 'read' && d.text?.trim()).map((d) => `=== ${d.kind}: ${d.name} ===\n${preparedText(d.kind, d.text!).text}`).join('\n\n');
  const row = { id: k.id, company: k.company, profile: { status: prof.status, chars: prof.text?.length ?? 0, pages: prof.pages ?? null, reason: prof.reason ?? null },
    licence: { status: lic.status, activities: lic.activities ?? [] }, model_chars: given.length, model_parts: modelParts(given).length, text_head: (prof.text ?? '').slice(0, 300),
    // deno-lint-ignore no-explicit-any
    runs: [] as any[] };
  if (!MODEL) await Deno.writeTextFile(`${dir}/${k.id}.read.txt`, given);   // the text the model is given, beside the PDFs (outside the repo)
  for (let r = 0; MODEL && r < REPEATS; r++) {
    const t0 = Date.now();
    calls.length = 0;
    const reading = await readTogether([prof, lic], deps, k.company);
    const ms = Date.now() - t0;
    const laid = withReading([prof, lic], reading);
    const sl = servicesAndLicence(reading, laid);
    // deno-lint-ignore no-explicit-any
    row.runs.push({ ms, ok: reading.ok, why: (reading as any).why ?? null, error: (reading as any).error ?? null, held: (reading as any).held ?? null,
      // deno-lint-ignore no-explicit-any
      trades: reading.ok ? reading.trades.map((t: any) => ({ code: t.code, quote: t.snippet, reason: t.phrases?.[0] })) : [],
      // deno-lint-ignore no-explicit-any
      services: reading.ok ? reading.services.map((s: any) => ({ key: s.key, label: s.label_en, quote: s.snippet, licence: s.licence })) : [],
      rejected: reading.ok ? reading.rejected : [], licence_check: sl.licence_check,
      // deno-lint-ignore no-explicit-any
      doc_states: laid.map((d: any) => ({ kind: d.kind, status: d.status, choice: d.choice ?? null, reason: d.reason ?? null })),
      // reader @5: the delivery of each listed service, the questions (umbrella apart, for the scorer), his own words, the reading's times
      ...(reading.ok && reading.profile ? (() => { const p = reading.profile; return {
        // deno-lint-ignore no-explicit-any
        services: [...p.tick.map((x: any) => ({ key: x.key, delivery: 'own', quote: x.quote })), ...p.partner.map((x: any) => ({ key: x.key, delivery: 'partner', quote: x.quote }))],
        // deno-lint-ignore no-explicit-any
        vague: p.questions.filter((q: any) => q.kind !== 'umbrella').map((q: any) => ({ kind: q.kind, ask: q.prompt_en, status: q.status, options: q.options.map((o: any) => ({ label: o.label_en, keys: o.key ? [o.key] : [] })) })),
        // deno-lint-ignore no-explicit-any
        also_ask: p.questions.filter((q: any) => q.kind === 'umbrella').map((q: any) => ({ status: q.status, options: q.options.map((o: any) => ({ label: o.label_en, keys: o.key ? [o.key] : [] })) })),
        questions: p.questions, own_words: p.own_words, times: p.times, summary: p.summary, licence: p.licence, evidence: p.evidence, rejected: p.rejected }; })() : {}),
      recorded: calls.map((c) => ({ ...c })),
      given_docs: [prof, lic].filter((d) => d.status === 'read' && d.text?.trim()).map((d) => ({ path: d.path, name: d.name, kind: d.kind, text: preparedText(d.kind, d.text!).text, activities: d.activities ?? [] })) });
    console.log(`${k.id} run ${r + 1}: ${ms} ms, ok=${reading.ok}, trades=${reading.ok ? reading.trades.map((t: { code: string }) => t.code).join('+') : (reading as { why: string }).why}, services=${reading.ok ? reading.services.length : 0}`);
  }
  if (!MODEL) console.log(`${k.id}: profile ${prof.status} ${row.profile.chars} chars, licence activities ${JSON.stringify(row.licence.activities)}, model text ${row.model_chars} chars in ${row.model_parts} part(s)`);
  out.push(row);
  await Deno.writeTextFile(outPath, JSON.stringify(out, null, 1));
  if (catalogue) await Deno.writeTextFile(outPath.replace(/\.json$/, '') + '.catalogue.json', JSON.stringify(catalogue));
}
