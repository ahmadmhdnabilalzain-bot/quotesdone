// THE VERIFIED KNOWLEDGE PACKS: what a pack must be, where each one lives, and the rows it becomes.
// Seat: it_engineer (the shared knowledge platform); each pack is owned by the seat it serves. 23 Sep 2026.
//
// Side-effect free: imported by the loader (scripts/kb/load_verified_packs.mjs), the retrieval eval
// (scripts/eval/knowledge_pack_eval.mjs) and the check (scripts/checks/every_seat_reads_its_verified_pack.test.mjs),
// so all three run the SAME gate, the SAME row mapping and the SAME embedding recipe. A copy in each would
// prove that a copy works.
//
// The source of truth is the repository copy: knowledge/packs/<trade>.json (and <trade>.market.json, the
// UAE market file for that trade) and knowledge/seats/<seat>.json. Shape:
//   { trade|seat, entries: [{id, topic, topic_ar?, kind, body_en, body_ar, sources[], confidence, as_of,
//     area?, required_specs?, gap_kind?, source_note?}], eval: [{q_en, q_ar, expected_entry_ids[]}], verified: {...} }
import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { tmpdir } from 'node:os';

export const SEATS = ['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'];
// Where a seat pack lives: the seat's own table, the one fn_reason_retrieve reads for that seat.
export const SEAT_TABLE = {
  sales_engineer: 'sales_knowledge', customer_support: 'support_knowledge', accountant: 'accountant_knowledge',
  it_engineer: 'it_engineer_knowledge', ceo: 'ceo_knowledge', marketing: 'marketing_knowledge',
};
// Which seats reason from a trade pack (sales_knowledge rows tagged trade:<code>).
export const TRADE_SEATS = ['sales_engineer', 'customer_support'];
export const TABLES = [...new Set(Object.values(SEAT_TABLE))];
// THE COMPANY'S OWN FACTS ARE INTERNAL (ceo, 19 Oct 2026, #1567). An entry of a SEAT pack whose kind is 'company', or
// that cites an internal:founder_instruction/... or internal:memory/... source, states QuotesDone's own thresholds, owners
// and routines. Its rows carry the tag 'audience:internal', and fn_reason_retrieve / fn_reason_retrieve_ml never return
// them to a customer, supplier or visitor (or a call that names no audience). A trade pack is public. The seat cards
// (scripts/kb/compile_brief.mjs) are compiled from exactly these entries.
export const isOwnEntry = (e) => e.kind === 'company' || (e.sources ?? []).some((x) => /^internal:(founder_instruction|memory)\//.test(x));

// THE STATING RULE (founder, 7 Oct 2026): an entry with low confidence, or carrying any fact that was not read on a
// page actually opened, is stored verified=false and is never stated to a customer or a supplier. It is kept in its
// pack and loaded (so the gap is on record and can be verified later), but its rows carry runtime_index_eligible =
// false, and every retrieval a seat answers from (fn_reason_retrieve, fn_reason_retrieve_ml) reads only eligible rows.
export const isVerified = (e) => e.verified !== false && e.confidence !== 'low';
// The ml path reads support_knowledge and ceo_knowledge through knowledge_vector_ml without that filter, so a seat pack
// for those two seats may not hold an unverified entry at all.
const UNFILTERED_SEATS = ['customer_support', 'ceo'];

const sha = (s) => createHash('sha256').update(s).digest('hex');
const AR = /[؀-ۿ]/;

// THE GATE, identical to the knowledge programme's x/gate.js (the rule the packs were verified against):
// a pack is verified when it carries a `verified` block and at most 10% of its entries are unsourced or a
// low-confidence TECHNICAL claim. A commercial gap (price, lead time, warranty, contract) marked "not
// established" is an honest answer, not a failure (coordinator ruling, PROGRESS.md).
const COM = /price|cost|lead.?time|warrant|amc|contract|payment|rental|mistake|red.?flag/i;
// An entry DECLARED verified=false is quarantined: it is stored for the record, never retrievable (isVerified), and so
// not part of what the pack serves; the 10% rule is measured over the entries the pack serves. An entry that is low
// confidence but NOT declared still counts against the pack, exactly as before (7 Oct 2026).
export function gate(pack) {
  const served = pack.entries.filter((e) => e.verified !== false);
  const bad = served.filter((e) => {
    const src = (e.sources || []).length > 0;
    const ne = /not established/i.test(e.body_en);
    const commercial = e.gap_kind === 'commercial' || (!e.gap_kind && (COM.test(e.id) || /price_driver|lead_time|warranty|buyer_mistake|quote_red_flag/.test(e.kind || '')));
    if (commercial) return false;
    if (!src && !ne) return true;
    return e.confidence === 'low' || (!src && ne);
  });
  const ok = !!pack.verified && typeof pack.verified === 'object' && served.length > 0 && bad.length / served.length <= 0.1;
  return { ok, bad: bad.map((e) => e.id) };
}

/** Every refusal for one pack, named. `code` is the trade or seat the file is for. */
// sibling: the entry ids of the SAME trade's other file (<trade>.json for <trade>.market.json). A market question may
// name one only with expected_mode 'any' and a why (7 Oct 2026: judged by a fresh agent that saw only the question and
// the entry text and accepted it only if it alone fully answers). Never another trade's entry.
export function validate(pack, kind, code, sibling = new Set()) {
  const err = [];
  const owner = kind === 'trade' ? pack.trade : pack.seat;
  if (owner !== code) err.push(`${kind} is ${JSON.stringify(owner)}, file is for ${code}`);
  if (kind === 'seat' && !SEATS.includes(code)) err.push(`${code} is not a seat`);
  if (!Array.isArray(pack.entries) || !pack.entries.length) return [...err, 'no entries'];
  const ids = new Set();
  for (const e of pack.entries) {
    const at = e?.id ?? '(no id)';
    if (typeof e.id !== 'string' || !e.id.startsWith(code + ':')) err.push(`${at}: id must start with ${code}:`);
    if (e.id?.includes('@')) err.push(`${at}: '@' is reserved for the Arabic row`);
    if (ids.has(e.id)) err.push(`${at}: duplicate id`);
    ids.add(e.id);
    for (const f of ['topic', 'kind', 'body_en', 'body_ar', 'as_of']) if (typeof e[f] !== 'string' || !e[f].trim()) err.push(`${at}: ${f} missing`);
    if (typeof e.body_ar === 'string' && !AR.test(e.body_ar)) err.push(`${at}: body_ar is not Arabic`);
    if (e.topic_ar !== undefined && (typeof e.topic_ar !== 'string' || !AR.test(e.topic_ar))) err.push(`${at}: topic_ar is not Arabic`);
    if (!Array.isArray(e.sources)) err.push(`${at}: sources must be an array`);
    if (!['high', 'medium', 'low'].includes(e.confidence)) err.push(`${at}: confidence ${e.confidence}`);
    if (e.verified !== undefined && typeof e.verified !== 'boolean') err.push(`${at}: verified must be true or false`);
    if (kind === 'seat' && UNFILTERED_SEATS.includes(code) && !isVerified(e)) err.push(`${at}: an unverified entry cannot sit in the ${code} pack (its ml retrieval does not filter)`);
    if (e.area !== undefined && !/^[a-z_]+$/.test(e.area)) err.push(`${at}: area must be a lowercase_word, got ${JSON.stringify(e.area)}`);
    // THE EXPERT INTERVIEW FIELDS (sales_engineer, 10 Nov 2026, ledger 1587-1590). A blocking spec the checklist does not
    // require, or a guide row for a spec it does not list, is a rule nobody can satisfy: the loader would mark nothing and
    // the interview would ask for something no quote line carries. A brand tier outside the four words cannot be turned
    // into the generic description that replaces a supplier-identifying brand.
    const req = new Set((e.required_specs ?? []).map(String));
    if (e.blocking !== undefined) {
      if (!Array.isArray(e.blocking)) err.push(`${at}: blocking must be an array`);
      else for (const b of e.blocking) if (!req.has(String(b))) err.push(`${at}: blocking spec ${JSON.stringify(b)} is not in required_specs`);
    }
    if (e.spec_guide !== undefined) {
      if (!Array.isArray(e.spec_guide)) err.push(`${at}: spec_guide must be an array`);
      else {
        for (const g of e.spec_guide) if (!req.has(String(g?.spec)) || typeof g.blocking !== 'boolean' || !String(g.why_it_prices ?? '').trim() && g.blocking) err.push(`${at}: spec_guide row ${JSON.stringify(g?.spec)} is malformed or not in required_specs`);
        const blk = new Set(e.spec_guide.filter((g) => g.blocking).map((g) => String(g.spec)));
        if (blk.size !== (e.blocking ?? []).length || (e.blocking ?? []).some((b) => !blk.has(String(b)))) err.push(`${at}: spec_guide blocking rows and the blocking list disagree`);
      }
    }
    for (const b of e.brand_profiles ?? []) {
      if (!b?.brand || !b.origin_country || !['economy', 'mid', 'premium', 'luxury', 'dealer', 'operator'].includes(b.tier) || !String(b.generic_en ?? '').trim() || !AR.test(String(b.generic_ar ?? '')))
        err.push(`${at}: brand_profiles row ${JSON.stringify(b?.brand)} needs origin_country, a tier (economy/mid/premium/luxury/dealer/operator) and generic_en/generic_ar`);
    }
  }
  for (const q of pack.eval ?? []) {
    if (!q.q_en || !q.q_ar || !Array.isArray(q.expected_entry_ids) || !q.expected_entry_ids.length) err.push(`eval: malformed ${JSON.stringify(q).slice(0, 80)}`);
    for (const x of q.expected_entry_ids ?? []) if (!ids.has(x) && !(sibling.has(x) && q.expected_mode === 'any')) err.push(`eval: expects ${x}, not in the pack`);
    // 'any' = each named entry answers the question; it must name 2+ entries and say why, per question.
    if (q.expected_mode !== undefined && (q.expected_mode !== 'any' || (q.expected_entry_ids ?? []).length < 2 || !String(q.why ?? '').trim()))
      err.push(`eval: expected_mode must be 'any' with 2+ entries and a why: ${String(q.q_en).slice(0, 60)}`);
  }
  const g = gate(pack);
  if (!g.ok) err.push(`not verified: ${pack.verified ? `${g.bad.length}/${pack.entries.filter((e) => e.verified !== false).length} served entries unsourced or low-confidence technical` : 'no verified block'}`);
  return err;
}

/** The pack files in a directory tree laid out as packs/ and seats/ (the scratchpad or the repo's knowledge/). */
export function listPackFiles(root) {
  const out = [];
  for (const [dir, kind] of [['packs', 'trade'], ['seats', 'seat']]) {
    const d = join(root, dir);
    if (!existsSync(d)) continue;
    for (const f of readdirSync(d).sort()) {
      const m = f.match(/^([a-z_]+)(\.market)?\.json$/);
      if (!m || (kind === 'seat' && m[2])) continue;   // *.draft.json, *.pre*.json never match
      out.push({ kind, code: m[1], key: m[1] + (m[2] ?? ''), file: join(d, f), rel: `${dir}/${f}` });
    }
  }
  return out;
}

/** Read and validate every pack under root; ids must be unique across ALL packs (they share tables). */
export function readPacks(root) {
  const packs = listPackFiles(root).map((p) => {
    const text = readFileSync(p.file, 'utf8');
    let pack; try { pack = JSON.parse(text); } catch (e) { return { ...p, errors: ['not JSON: ' + e.message] }; }
    const version = 'sha256:' + sha(text).slice(0, 16);
    const pack_id = `verified:${p.kind}:${p.key}`;
    let sib = new Set();
    if (p.key.endsWith('.market')) { const t = join(root, 'packs', p.code + '.json'); if (existsSync(t)) try { sib = new Set(JSON.parse(readFileSync(t, 'utf8')).entries.map((e) => e.id)); } catch { /* the sibling's own validation reports it */ } }
    return { ...p, pack, version, pack_id, errors: validate(pack, p.kind, p.code, sib) };
  });
  const seen = new Map();
  for (const p of packs) for (const e of p.pack?.entries ?? []) {
    if (seen.has(e.id) && seen.get(e.id) !== p.rel) p.errors.push(`${e.id}: also in ${seen.get(e.id)}`);
    seen.set(e.id, p.rel);
  }
  return packs;
}

/** The seats whose decision-time retrieval reads this pack. */
export const seatsOf = (p) => (p.kind === 'trade' ? TRADE_SEATS : [p.code]);
export const tableOf = (p) => (p.kind === 'trade' ? 'sales_knowledge' : SEAT_TABLE[p.code]);
/** A retrieved row id back to its entry id ('<id>@ar' is the Arabic row of '<id>'). */
export const entryOf = (recordId) => String(recordId).replace(/@ar$/, '');

const url = (s) => (typeof s === 'string' ? s : s?.url ?? s?.href ?? JSON.stringify(s));

/** One pack -> its rows: every entry twice (English '<id>', Arabic '<id>@ar'), in the columns of its table. */
export function rowsOf(p) {
  const table = tableOf(p);
  const now = new Date().toISOString();
  return p.pack.entries.flatMap((e) => ['en', 'ar'].map((lang) => {
    const record_id = lang === 'en' ? e.id : e.id + '@ar';
    const body = lang === 'en' ? e.body_en : e.body_ar;
    // THE ARABIC ROW IS TITLED IN ARABIC when the entry carries topic_ar (6 Oct 2026, it_engineer). Measured: every
    // '<id>@ar' row was embedded as an ENGLISH title over an Arabic body, so the one line naming the trade was in the
    // language the Arabic question was not. The 205 market packs share one Arabic body template, and the multilingual
    // model ranked another trade's Arabic twin first: ml-path Arabic recall@5 0.672, 134 of 412 (pack, seat) pairs at 0.
    // Re-embedded with the Arabic title, the same rows and questions read 0.964 on the multilingual space alone.
    const title = lang === 'ar' && e.topic_ar ? e.topic_ar : e.topic;
    const sources = (e.sources ?? []).map(url);
    // area: the seat's own subject area (founder instructions 889/893/894, 28 Sep 2026), so a lookup can narrow to
    // the right area before ranking by meaning. Optional: a pack without it loads exactly as before.
    const tags = [...(p.kind === 'trade' ? ['trade:' + p.code] : []), 'verified_pack', 'lang:' + lang, 'kind:' + e.kind,
      ...(e.area ? ['area:' + e.area] : []), 'confidence:' + e.confidence, 'verified:' + isVerified(e),
      ...(p.kind !== 'trade' && isOwnEntry(e) ? ['audience:internal'] : [])];
    const eligible = isVerified(e);
    const sd = { entry_id: e.id, lang, verified: eligible, kind: e.kind, area: e.area ?? null, confidence: e.confidence, as_of: e.as_of, gap_kind: e.gap_kind ?? null,
      required_specs: e.required_specs ?? null, blocking: e.blocking ?? null, spec_guide: e.spec_guide ?? null,
      firm_price_condition: e.firm_price_condition ?? null, brand_profiles: e.brand_profiles ?? null,
      source_note: e.source_note ?? null, sources: e.sources ?? [], pack_file: p.rel };
    const b = sha(body);
    let cols;
    if (table === 'support_knowledge') {
      cols = { record_id, schema_version: 'verified_pack.v1', record_version: p.version, record_kind: 'verified_pack_entry', title,
        domain: e.kind, tags, language: lang, review_status: 'verified_sourced', content_origin: 'verified_pack', authority_effect: 'none',
        runtime_use: 'retrieval', runtime_index_eligible: eligible, contains_synthetic_example: false,
        requires_current_verification: e.confidence !== 'high', source_ids: sources, source_path: sources[0] ?? null,
        structured_data: sd, body, body_sha256: b, pack_id: p.pack_id, pack_version: p.version, imported_at: now };
    } else if (table === 'ceo_knowledge') {
      // ceo_knowledge has no pack_id; the pack is in tags ('pack:<id>') and in extra.
      cols = { record_id, schema_version: 'verified_pack.v1', record_version: p.version, record_kind: 'verified_pack_entry', title,
        domain: e.kind, tags: [...tags, 'pack:' + p.pack_id], language: lang, company_scope: 'industry', review_status: 'verified_sourced',
        content_origin: 'verified_pack', authority_effect: 'none', runtime_use: 'retrieval', runtime_index_eligible: eligible,
        external_execution_enabled: false, contains_synthetic_example: false, requires_current_verification: e.confidence !== 'high',
        source_ids: sources, source_path: sources[0] ?? null, body, body_sha256: b, extra: { ...sd, pack_id: p.pack_id },
        pack_fingerprint: p.version, imported_at: now };
    } else {
      cols = { record_id, record_type: 'verified_pack_entry', domain: e.kind, title, content: body, structured_data: sd,
        source_ids: sources, epistemic_status: 'verified_pack_sourced', jurisdiction: 'AE', pack_id: p.pack_id, pack_version: p.version,
        body_sha256: b, runtime_index_eligible: eligible, authority_effect: 'none', tags, updated_at: now };
      if (table === 'sales_knowledge') Object.assign(cols, { record_version: p.version, content_sha256: b });
    }
    // The text embedded: title + newline + body, the recipe every other knowledge vector in this estate uses
    // (scripts/kb/embed_sales_knowledge.mjs); the gateway cuts it at 1,200 characters, as runtime does.
    return { table, record_id, entry_id: e.id, lang, text: title + '\n' + body, cols };
  }));
}

// ── SQL literals (the management API takes one statement string; no parameters) ─────────────────
export const lit = (v) => (v === null || v === undefined ? 'null'
  : typeof v === 'boolean' ? String(v)
  : Array.isArray(v) ? (v.length ? `array[${v.map(lit).join(',')}]::text[]` : `'{}'::text[]`)
  : typeof v === 'object' ? `${lit(JSON.stringify(v))}::jsonb`
  : "'" + String(v).replace(/'/g, "''") + "'");
export const vecLit = (v) => `'[${v.join(',')}]'::vector(384)`;

/** One upsert statement for rows of ONE table; each row carries its vector. Re-running replaces, never duplicates. */
export function upsertSql(table, rows) {
  const cols = [...Object.keys(rows[0].cols), 'embedding_gte'];
  const values = rows.map((r) => `(${Object.keys(rows[0].cols).map((c) => lit(r.cols[c])).join(',')},${vecLit(r.vec)})`).join(',\n');
  const set = cols.filter((c) => c !== 'record_id').map((c) => `${c} = excluded.${c}`).join(', ');
  return `insert into public.${table} (${cols.join(',')}) values\n${values}\non conflict (record_id) do update set ${set};\n`;
}

// ── the free in-region embedder: ai_gateway {action:'embed'} -> gte-small, the path think() uses ───
// Cached by the sha256 of the text in the OS temp directory (never the repository), so the loader and the
// eval embed each text once. A refusal is an error, never a vector: a fabricated vector would rank nonsense.
export async function makeEmbedder(sql, projectRef, { cachePath = join(tmpdir(), 'qd_verified_pack_embeddings.json') } = {}) {
  const secret = (await sql(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  if (!secret) throw new Error('no cred_fn_ai in app_secrets');
  const cache = existsSync(cachePath) ? JSON.parse(readFileSync(cachePath, 'utf8')) : {};
  let dirty = 0;
  const save = () => { if (dirty) { writeFileSync(cachePath, JSON.stringify(cache)); dirty = 0; } };
  async function one(text) {
    const k = sha(text);
    if (cache[k]) return cache[k];
    for (let attempt = 0; ; attempt++) {
      const res = await fetch(`https://${projectRef}.supabase.co/functions/v1/ai_gateway`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: secret, fn: 'embed_verified_packs', action: 'embed', text }),
      }).catch((e) => ({ ok: false, status: 0, text: async () => String(e.message) }));
      const j = res.ok ? await res.json() : null;
      const v = typeof j?.embedding === 'string' ? JSON.parse(j.embedding) : j?.embedding;
      if (Array.isArray(v) && v.length === 384) { cache[k] = v; if (++dirty >= 50) save(); return v; }
      if (attempt >= 4) throw new Error(`embedding refused (HTTP ${res.status}): ${res.ok ? 'no vector' : (await res.text()).slice(0, 160)}`);
      await new Promise((r) => setTimeout(r, 1500 * 2 ** attempt));
    }
  }
  async function many(texts, conc = 6) {
    const out = new Array(texts.length);
    let i = 0;
    await Promise.all(Array.from({ length: conc }, async () => { while (i < texts.length) { const j = i++; out[j] = await one(texts[j]); } }));
    save();
    return out;
  }
  return { one, many, save };
}

export const cosine = (a, b) => { let s = 0; for (let i = 0; i < a.length; i++) s += a[i] * b[i]; return s; };  // gte vectors are normalised
