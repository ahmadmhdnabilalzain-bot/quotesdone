// PROTOTYPE v3 of the DESIGNED profile reading (REPORT.md part 3): the form the design recommends. NOT product code.
// Differences from read_profiles_v2.ts: (1) the READING is given the 223 trade NAMES (no services) and assigns each claim its trade;
// (2) the MAPPING is given only the services of those trades, their curated adjacent trades and their umbrella parents and children,
// not all 1,104; (3) the reading's effort is a parameter (QD_EFFORT_READ, default medium) so the clock can be measured.
// TWO CALLS, as the design has them (one call with the catalogue AND the full reading ran past the gateway's wall: HTTP 504 at 150 s on
// H01, kept as read_profiles_v2_onecall_504.ts):
//   A. THE READING, without the catalogue: everything the documents evidence, each with its sentence and its basis (stated / shown /
//      partner / brand), the vague statements with the question to ask, the umbrella candidates, brands, areas, roles.
//   B. THE MAPPING, with the catalogue: each phrase of A -> the service keys it IS, or none (the supplier's own words are kept).
// Same model and route as production (model_policy 'supplier_trade_choice', the deployed ai_gateway, 115 s a call). Code checks what the
// product would: every quote is in the profile (never the licence), every key is in the catalogue.
//   deno run -A --unsafe-proto --no-lock --node-modules-dir=auto read_profiles_v2.ts <profiles dir> <out.json> [--repeats 1] [--only H01]
const REPO = Deno.env.get('QD_REPO') || '/tmp/claude-0/main-base';
const S = `file://${REPO}/supabase/functions/_shared/`;
const { readDocForTrades, preparedText } = await import(S + 'supplier_doc_trades.ts');
const { tradeDefs, quoteFinder, answerJson } = await import(S + 'supplier_trade_choice.ts');
const { createClient } = await import('jsr:@supabase/supabase-js@2');
const [dir, outPath] = Deno.args;
const val = (f: string) => { const i = Deno.args.indexOf(f); return i >= 0 ? Deno.args[i + 1] : null; };
const REPEATS = Number(val('--repeats') || 1), ONLY = val('--only')?.split(',') ?? null;
const TAG = Deno.env.get('QD_RUN_TAG')!, SUBJECT = JSON.parse(Deno.env.get('QD_SUBJECT') || 'null');
if (!/^[a-z0-9]{4,16}$/.test(TAG || '') || !SUBJECT) { console.error('needs QD_RUN_TAG and QD_SUBJECT (the driver opens the window)'); Deno.exit(2); }
const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': Deno.env.get('QD_E2E_SECRET') || '' };
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
const { activeServiceRows } = await import(S + 'service_vocabulary.ts');
// THE FULL CATALOGUE, PAGED. supplier_trade_choice.tradeDefs reads taxonomy_trade_service unpaged and gets 1,000 of 1,104 rows
// (count_defs.mjs, 12 Nov 2026); the designed reader reads it through service_vocabulary.activeServiceRows, as the rewrite path does.
const cut = await tradeDefs(admin);
const { data: svcRows, error: svcErr } = await activeServiceRows(admin, 'trade_code,code,label_en,sort');
const { data: tradeRows } = await admin.from('taxonomy_trade').select('code,label').eq('active', true).order('code');
if (!cut || svcErr || !tradeRows?.length) { console.error('the trade list could not be read'); Deno.exit(2); }
// deno-lint-ignore no-explicit-any
const defs = (tradeRows as any[]).map((t) => ({ code: t.code, label: t.label, serviceKeys: (svcRows as any[]).filter((r) => r.trade_code === t.code).map((r) => ({ key: `${r.trade_code}.${r.code}`, label: r.label_en })) }));
// deno-lint-ignore no-explicit-any
console.log(`catalogue: ${defs.reduce((n: number, d: any) => n + d.serviceKeys.length, 0)} service keys (production's tradeDefs returned ${cut.reduce((n: number, d: any) => n + (d.serviceKeys?.length ?? 0), 0)})`);
const { data: sec } = await admin.from('app_secrets').select('value').eq('key', 'cred_fn_ai').maybeSingle();
const cred = sec?.value as string;
// deno-lint-ignore no-explicit-any
const list = defs.map((d: any) => `${d.code} = ${d.label} (services: ${d.serviceKeys.map((s: any) => `${s.key} = ${s.label}`).join('; ')})`).join('\n');
// deno-lint-ignore no-explicit-any
const { data: adjRows } = await admin.from('taxonomy_trade_adjacent').select('a_code,b_code,active');
const { data: umbRows } = await admin.from('taxonomy_trade').select('code,umbrella_code').eq('active', true);
// deno-lint-ignore no-explicit-any
const tradeList = defs.map((d: any) => `${d.code} = ${d.label}`).join('\n');
const EFFORT_READ = Deno.env.get('QD_EFFORT_READ') || 'medium', EFFORT_MAP = Deno.env.get('QD_EFFORT_MAP') || 'high';
// the catalogue slice the mapping is given: the named trades, their adjacent trades, their umbrella parent and children
function sliceFor(named: string[]): string {
  const T = new Set(named);
  for (const r of (adjRows || []) as { a_code: string; b_code: string; active: boolean }[]) { if (!r.active) continue; if (named.includes(r.a_code)) T.add(r.b_code); if (named.includes(r.b_code)) T.add(r.a_code); }
  for (const r of (umbRows || []) as { code: string; umbrella_code: string | null }[]) { if (r.umbrella_code && named.includes(r.umbrella_code)) T.add(r.code); if (named.includes(r.code) && r.umbrella_code) T.add(r.umbrella_code); }
  // deno-lint-ignore no-explicit-any
  return defs.filter((d: any) => T.has(d.code)).map((d: any) => `${d.code} = ${d.label} (services: ${d.serviceKeys.map((x: any) => `${x.key} = ${x.label}`).join('; ')})`).join('\n');
}
const KEYS = new Set<string>(defs.flatMap((d: any) => d.serviceKeys.map((s: any) => s.key))), TRADES = new Set<string>(defs.map((d: any) => d.code));

export const READ_SYSTEM = `You are the sales engineer of a UAE business-to-business procurement marketplace. You read ALL the documents one supplier company uploaded (company profile, catalogues, trade licence) the way an experienced person would, to understand everything this company can do for a customer. Your reading decides which customer requests reach this supplier: a service you miss is business the supplier never sees, and a service you invent is a request sent to a company that cannot quote it.

Our trades (code = name). Use them only to say which trade a service belongs to:
${tradeList}

Return STRICT JSON only, in this shape:
{"summary":"two plain English sentences saying what this company is and does",
 "evidence":[{"words":"a short English name for this ONE service or product line as a customer would ask for it, at most 8 words (translate Arabic)","quote":"ONE line copied EXACTLY, word for word, from the documents, in its original language, that shows it","basis":"stated|shown|partner|brand","partner_name":null,"trade":"the trade code it belongs to, or null when none of our trades covers it"}],
 "vague":[{"quote":"the vague line, copied exactly","why":"what a customer request could not be matched on","ask":"the one short question a sharp sales engineer would ask the supplier, in plain English","options":[{"label":"a specific option, 1 to 5 words","trade":"trade code or null"}]}],
 "also_ask":[{"because":"the evidence that makes these likely, in a few words","options":[{"label":"1 to 5 words","trade":"trade code or null"}]}],
 "licence":{"covers_profile":"yes|partly|no|no_licence","note":"one sentence when the licence and the other documents disagree, else empty"},
 "brands":[{"name":"brand","relation":"authorised_distributor|stocked|used","goods":"what that brand's goods are, a few words"}],
 "areas":["emirates the documents say the company serves"],
 "roles":["at most two of: manufacturer|distributor|supplier|installer|contractor|turnkey_fitout|maintenance|consultant"]}

RULES
1. EVERYTHING THE DOCUMENTS EVIDENCE, ONE ITEM EACH. A broad word covers many services: list every SPECIFIC service or product line the documents show, one evidence item per service (a line naming three services is three items, each quoting that line). One item per distinct service a customer would ask for: do not split one service into its parts (planting, lawns and palm trees are one item, garden planting). Read the whole text: lists, headings, sentences, project captions, brand lists.
2. BASIS says how the documents show it.
   "stated": the company says it offers this: an item of its services or products list, a heading, its title or tagline, or a sentence saying what it does.
   "shown": it appears only in the company's own project descriptions or captions (work it has done), not in a statement of what it offers.
   "partner": the documents say it is delivered through a partner, a subcontractor, a sister or group company, the manufacturer, or is "arranged", "managed" or "provided" through someone else. Give "partner_name" when the documents name them. Never mark partner work as stated.
   "brand": it follows only from a brand the company lists (a named brand's goods are a product line the documents do not otherwise state).
3. THE QUOTE IS THE PROOF. Copy it exactly from a document that is NOT the trade licence. The trade licence lists permitted activities; it says what the company may do, not what it does, so nothing is evidenced from the licence alone.
4. NEVER FROM: the company's or another company's name, a client, a certificate or standard it holds, a policy, a value, a vision or mission statement, a slogan, its staff or organisation chart, equipment or software it uses in its own work, or an internal function. History the company has left behind ("founded as a garments trader") is not a service. A FEATURE of how it delivers its service is not a service of its own: the visas, insurance and accommodation of the staff it supplies, delivery of its own goods, a warranty, a replacement guarantee, a helpdesk, a free site visit.
5. GOODS ARE NOT WORKS. Name goods as goods ("power tools supply") and works as works ("AC installation"). A company that only sells is never given installation or contracting work unless the documents say it does that work.
6. VAGUE. A statement of what the company OFFERS is vague when it names a category without saying the thing: "we supply staff and similar services", "all kinds of building materials", "all kinds of maintenance works", "and much more", "etc.", "solutions". Do NOT turn a vague statement into evidence items for services it does not name. Put it in "vague" with ONE question and 4 to 9 specific options a UAE company of this kind commonly offers, most common first. THE QUESTION ASKS FOR THE SPECIFIC KINDS OF THE MAIN THING LEFT OPEN: for a company that supplies staff, what sort of staff (general labourers, skilled tradesmen, drivers, cleaners, security guards, hospitality staff, office staff, engineers and technicians, freelancers); for a materials trader, which materials it stocks; for a maintenance company, which works it carries out. Never ask a general "what other services do you provide" question while the main offer itself is unspecified. When a line is partly specific ("A/C, plumbing, electrical, etc."), the named things are evidence items and the open part is a vague entry. A slogan or a marketing sentence is not a vague statement of offer. At most 3 vague entries, the one about the company's main offer first.
7. ALSO ASK (thinking of everything they can do). Think of what a company of this kind commonly does beyond what its documents show: at most 8 options in total, most likely first, only services a real company like this one is likely to do, never something already in "evidence" or "vague". Leave it empty when the documents are already complete and specific. These become questions to the supplier; they are never assumed.
8. NOTHING THERE. When the documents do not say what the company does, return "evidence":[] and one "vague" entry asking what the company does, with "options":[].
9. English only in "summary", "words", "ask", "why", "because" and every option. Quotes stay in the document's language.`;

export const mapSystem = (slice: string) => `You map short descriptions of a UAE supplier's services and products onto our catalogue of service keys. This is the part of the catalogue for this supplier's trades. Each line is: trade code = trade name (services: service key = service name; ...).
${slice}

You are given numbered phrases; some carry the line of the supplier's document they came from, for context. For EACH phrase return the catalogue service keys whose name covers exactly that work or those goods.
RULES
1. THE KEY THAT NAMES THIS WORK, OR NONE. Usually one key, at most two (two only when the catalogue lists the same work under two trades, or the phrase names two things). A key fits when its name says the same work in other words ("monthly garden maintenance" is Garden maintenance). When no service key covers it, return "keys":[] - never a merely related key. A phrase with no key is kept in the supplier's own words; nothing is lost by leaving it empty.
2. "trade": the catalogue trade the phrase belongs to, when one does, even when no service key fits; otherwise null.
3. Goods are not works: a supply or trading phrase gets a goods key (a product line of a goods trade), never an installation or contracting key, and the reverse.
4. Judge the phrase by what it IS, not by a word in it.
Return STRICT JSON only: {"map":[{"i":1,"keys":["trade.service"],"trade":"trade code or null"}]}`;

type Ans = { ok: boolean; content: string; error?: string; ms: number };
async function ask(sys: string, text: string, effort: string): Promise<Ans> {
  const t0 = Date.now();
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const r = await fetch(Deno.env.get('SUPABASE_URL') + '/functions/v1/ai_gateway', { method: 'POST', headers, signal: AbortSignal.timeout(120_000),
        body: JSON.stringify({ __secret: cred, client_timeout_ms: 115_000, fn: 'supplier_doc_trades', task_class: 'supplier_trade_choice', subject: SUBJECT, temperature: 0, effort, sys_stable: sys, sys: '',
          input: [{ role: 'user', content: [{ type: 'text', text }] }] }) });
      const j = await r.json().catch(() => null);
      if (!r.ok || j?.ok === false) { if (attempt === 0 && r.status >= 500) continue; return { ok: false, content: '', error: `(${r.status}) ${String(j?.error || j?.detail || '').slice(0, 200)}`, ms: Date.now() - t0 }; }
      return { ok: true, content: String(j?.content ?? ''), ms: Date.now() - t0, ...(j?.truncated || j?.finish_reason === 'length' ? { error: 'cut off' } : {}) };
    } catch (e) { if (attempt === 1) return { ok: false, content: '', error: String((e as Error)?.message || e).slice(0, 200), ms: Date.now() - t0 }; }
  }
  return { ok: false, content: '', error: 'no answer', ms: Date.now() - t0 };
}

const keys = JSON.parse(await Deno.readTextFile(`${dir}/answer_keys.json`)).profiles as { id: string; company: string; profile: string; licence: string }[];
// deno-lint-ignore no-explicit-any
const out: any[] = [];
const str = (x: unknown) => String(x ?? '').trim();
for (const k of keys) {
  if (ONLY && !ONLY.includes(k.id)) continue;
  const doc = async (f: string, kind: 'profile' | 'licence') => await readDocForTrades({ path: `zz-demo-hard/${k.id}/${f}`, name: f, kind, bytes: new Uint8Array(await Deno.readFile(`${dir}/${f}`)),
    mime: /\.docx$/.test(f) ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' : 'application/pdf', names: [k.company] }, {}, { textOnly: true });
  const prof = await doc(k.profile, 'profile'), lic = await doc(k.licence, 'licence');
  const profText = preparedText('profile', prof.text ?? '').text, licText = preparedText('licence', lic.text ?? '').text;
  const given = `The company registered as: ${k.company}\n\nThe company's documents, each under its own header:\n\n=== profile: ${prof.name} ===\n${profText}\n\n=== licence: ${lic.name} ===\n${licText}`;
  const inProfile = quoteFinder(profText);
  // deno-lint-ignore no-explicit-any
  const row = { id: k.id, company: k.company, runs: [] as any[] };
  for (let r = 0; r < REPEATS; r++) {
    const a = await ask(READ_SYSTEM, given, EFFORT_READ);
    // deno-lint-ignore no-explicit-any
    const p = (a.ok ? answerJson(a.content, 'evidence') : null) as any;
    const rejected: { what: string; why: string }[] = [];
    // deno-lint-ignore no-explicit-any
    const items = (Array.isArray(p?.evidence) ? p.evidence : []).map((e: any) => ({ words: str(e?.words), quote: str(e?.quote), basis: str(e?.basis), partner_name: e?.partner_name ?? null, keys: [] as string[], trade: (TRADES.has(str(e?.trade)) ? str(e.trade) : null) as string | null }))
      .filter((e: { words: string; quote: string }) => { if (inProfile(e.quote)) return true; rejected.push({ what: e.words, why: `the quote is not in the profile: "${e.quote.slice(0, 70)}"` }); return false; });
    // deno-lint-ignore no-explicit-any
    const vague = (Array.isArray(p?.vague) ? p.vague : []).map((v: any) => ({ quote: str(v?.quote), in_doc: inProfile(str(v?.quote)), why: str(v?.why), ask: str(v?.ask), options: (Array.isArray(v?.options) ? v.options : []).map((o: any) => ({ label: str(o?.label ?? o), trade: TRADES.has(str(o?.trade)) ? str(o.trade) : null, keys: [] as string[] })) }));
    // deno-lint-ignore no-explicit-any
    const also = (Array.isArray(p?.also_ask) ? p.also_ask : []).map((v: any) => ({ because: str(v?.because), options: (Array.isArray(v?.options) ? v.options : []).map((o: any) => ({ label: str(o?.label ?? o), trade: TRADES.has(str(o?.trade)) ? str(o.trade) : null, keys: [] as string[] })) }));
    // B. the mapping: every phrase, numbered
    const phrases: { ref: { keys: string[]; trade?: string | null }; text: string }[] = [
      ...items.map((it: { words: string; quote: string; keys: string[] }) => ({ ref: it, text: `${it.words}  [from: ${it.quote.slice(0, 160)}]` })),
      ...vague.flatMap((v: { options: { label: string; keys: string[] }[] }) => v.options.map((o) => ({ ref: o, text: o.label }))),
      ...also.flatMap((v: { options: { label: string; keys: string[] }[] }) => v.options.map((o) => ({ ref: o, text: o.label }))) ];
    let b: Ans = { ok: true, content: '', ms: 0 };
    // deno-lint-ignore no-explicit-any
    const named = [...new Set(phrases.map((x: any) => x.ref.trade).filter(Boolean))] as string[];
    const mappable = phrases.map((x, i) => ({ ...x, n: i + 1 })).filter((x) => x.ref.trade);
    const chunks: (typeof mappable)[] = []; for (let i = 0; i < mappable.length; i += 15) chunks.push(mappable.slice(i, i + 15));
    const tB = Date.now(); const raws: string[] = []; let mapErr: string | undefined;
    const one = async (ch: typeof mappable) => {
      const r = await ask(mapSystem(sliceFor([...new Set(ch.map((x) => x.ref.trade as string))])), `Company: ${k.company}. ${str(p?.summary)}\n\nPhrases:\n${ch.map((x) => `${x.n}. ${x.text}`).join('\n')}`, EFFORT_MAP);
      if (!r.ok) { mapErr = r.error; return; }
      raws.push(r.content);
      // deno-lint-ignore no-explicit-any
      const m = answerJson(r.content, 'map') as any;
      // deno-lint-ignore no-explicit-any
      for (const e of (Array.isArray(m?.map) ? m.map : []) as any[]) {
        const ph = phrases[Number(e?.i) - 1]; if (!ph) continue;
        for (const key of (Array.isArray(e?.keys) ? e.keys : []).map(String)) { if (KEYS.has(key)) { if (!ph.ref.keys.includes(key)) ph.ref.keys.push(key); } else rejected.push({ what: key, why: 'not a catalogue service key' }); }
        if (TRADES.has(str(e?.trade))) ph.ref.trade = str(e.trade);
      }
    };
    for (let i = 0; i < chunks.length; i += 3) await Promise.all(chunks.slice(i, i + 3).map(one));
    b = { ok: !mapErr, content: raws.join('\n'), ms: chunks.length ? Date.now() - tB : 0, ...(mapErr ? { error: mapErr } : {}) };
    const services: { key: string; delivery: string; basis: string; quote: string; words: string }[] = [];
    for (const it of items) for (const key of it.keys) if (!services.some((s) => s.key === key)) services.push({ key, delivery: it.basis === 'partner' ? 'partner' : 'own', basis: it.basis, quote: it.quote, words: it.words });
    // a key evidenced both by the company's own work and by a partner line is the company's own
    for (const s of services) if (s.delivery === 'partner' && items.some((it: { basis: string; keys: string[] }) => it.basis !== 'partner' && it.keys.includes(s.key))) s.delivery = 'own';
    const trades = [...new Set([...services.filter((s) => s.delivery === 'own').map((s) => s.key.split('.')[0]), ...items.filter((i: { basis: string; trade: string | null }) => i.basis !== 'partner' && i.trade).map((i: { trade: string }) => i.trade)])].map((code) => ({ code }));
    row.runs.push({ map_calls: chunks.length, effort_read: EFFORT_READ, effort_map: EFFORT_MAP, named_trades: named, ms: a.ms + b.ms, ms_read: a.ms, ms_map: b.ms, ok: a.ok && !!p && b.ok, why: a.ok ? (p ? (b.ok ? null : 'map_unavailable') : 'not_json') : 'unavailable', error: a.error ?? b.error ?? null, trades, services, items,
      own_words: items.filter((i: { keys: string[] }) => !i.keys.length).map((i: { words: string; basis: string; trade: string | null; quote: string }) => ({ words: i.words, basis: i.basis, trade: i.trade, quote: i.quote })),
      vague, also_ask: also, questions: vague.map((v: { ask: string }) => v.ask), licence: p?.licence ?? null, brands: p?.brands ?? [], areas: p?.areas ?? [], roles: p?.roles ?? [], summary: p?.summary ?? null, rejected, raw_read: a.content, raw_map: b.content });
    console.log(`${k.id} v2 run ${r + 1}: read ${a.ms} ms + map ${b.ms} ms, ok=${a.ok && !!p && b.ok}${a.error || b.error ? ' ' + (a.error || b.error) : ''}, evidence=${items.length} (keys ${services.length}, own words ${items.filter((i: { keys: string[] }) => !i.keys.length).length}, partner ${items.filter((i: { basis: string }) => i.basis === 'partner').length}), vague=${vague.length}, also_ask=${also.reduce((n: number, x: { options: unknown[] }) => n + x.options.length, 0)}, rejected=${rejected.length}`);
  }
  out.push(row);
  await Deno.writeTextFile(outPath, JSON.stringify(out, null, 1));
}
