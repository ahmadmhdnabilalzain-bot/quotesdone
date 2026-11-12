// WHAT A SUPPLIER'S OWN DOCUMENTS SAY HE DOES, AS SERVICES; WHETHER HIS LICENCE COVERS IT; AND HIS OWN WORDS FOR IT
// (10 Nov 2026, sales_engineer; founder ledger 1573, 1579, 1586).
//
// Founder, 10 Nov 2026 (1573): "the agent reads the company profile and trade licence, understands what the company does,
// checks the licence activities against the profile, proposes extracted keywords/services the supplier ticks or adds to;
// those keywords drive the cross-matching". 1579: "for every trade, product and service, not just that case".
//
// MEASURED (design audit 10 Nov 2026, section 3.1-3.2): the profile proposed TRADES only (supplier_doc_trades.ts), so the
// supplier's own specific lines ("PVC decorative panels") were never offered as services; nothing compared the licence's
// activities with the profile; and a phrase a supplier confirmed could never become a name matching reads.
//
// WHAT LIVES HERE (pure, tested offline in profile_services.test.ts): the shapes the model's reading of a supplier's documents is
// stored and shown in (the reading itself is supplier_doc_trades.readTogether, since ruling 1627), and:
//   * aliasPairsOf: the supplier's own short phrases for services he CONFIRMED -> the alias queue
//     (public.fn_service_alias_propose); a phrase is a name only once the sales engineer approves it.
//   * stateServiceKeys: inquiry_state.specs.service_keys (written by the expert-advice catalogue, branch
//     sales_engineer-expert-advice) -> the request's exact service keys, preferred over reading its prose.
// prevented by: supabase/functions/_shared/profile_services.test.ts
// ── WHAT THE MODEL UNDERSTOOD THE SUPPLIER DOES, AS SERVICES (11 Nov 2026, customer_support; founder ruling 1627) ────────────
// servicesOfText (exact service names, then gte-small meaning with one head word) and proposedServicesOf (every service a document
// named, checked against the trades code read off the licence's activities) are DELETED: they were the word and vector reading
// ruling 1627 rejects, and the licence is not a source of services. The model now reads all the supplier's documents together and
// names each service with the line it understood it from and its own judgement of the licence (supplier_doc_trades.readTogether);
// these are the shapes it is stored and shown in.
export type ServiceHit = {
  key: string; trade: string; label_en: string;
  /** 'model': the reader model understood it (ruling 1627). Older records may say 'exact_name' or 'meaning'. */
  via: 'model' | 'exact_name' | 'meaning';
  /** the supplier's own words for it: the line the model quoted */
  phrase: string;
  /** the line of the document it was understood from */
  snippet: string;
  /** reader @5 (supplier_profile_reading.ts, 12 Nov 2026): 'partner' when the documents say it is delivered through someone else.
   *  Listed with its sentence, marked, never ticked by "Tick all"; asked own team or partner in slice 4. Absent: his own. */
  delivery?: 'own' | 'partner'; partner_name?: string | null;
};

export type LicenceStatus = 'supported' | 'not_covered' | 'unclear';
export type LicenceCheck = {
  /** a licence was read and its activities line could be read */
  read: boolean;
  activities: string[];
  /** kept for records written before 11 Nov 2026 (trades code read off the activities); nothing writes it now */
  licence_trades: string[];
  not_covered: string[];
  checked_at: string;
};
export type ProposedService = ServiceHit & { doc: string; licence: LicenceStatus };

// ── THE SUPPLIER'S OWN WORDS -> THE ALIAS QUEUE ──────────────────────────────────────────────────────────────────────
// A NAME IS A SHORT NOUN PHRASE: a line of a brochure is not proposed as one. Six words is the longest curated alias of the
// 1,103 services (measured 10 Nov 2026 on the live vocabulary: "supply and installation of AC units" style names).
export const ALIAS_MAX_WORDS = 6;
export type AliasPair = { phrase: string; key: string };
export function aliasPairsOf(candidates: { phrase: string; key: string }[], stated: string[]): AliasPair[] {
  const keep = new Set(stated);
  const out = new Map<string, AliasPair>();
  for (const c of candidates) {
    const phrase = String(c.phrase ?? '').replace(/\s+/g, ' ').trim().replace(/^[\s,.;:•·*\-–—]+|[\s,.;:•·*\-–—]+$/g, '');
    const words = phrase.split(' ').filter(Boolean).length;
    if (!keep.has(c.key) || phrase.length < 3 || phrase.length > 120 || words > ALIAS_MAX_WORDS) continue;
    const k = phrase.toLowerCase() + '|' + c.key;
    if (!out.has(k)) out.set(k, { phrase, key: c.key });
  }
  return [...out.values()].slice(0, 40);
}

// ── THE REQUEST'S SERVICES, FROM ITS STATE ───────────────────────────────────────────────────────────────────────────
// The expert-advice catalogue (branch sales_engineer-expert-advice) writes the option the customer chose as exact service
// keys into inquiry_state.specs.service_keys. A spec value is a string (inquiry_state.SpecEntry), so the keys arrive as
// "wallpaper.wall_panels" or a list joined by commas, spaces or "|"; an array is accepted too. Only key-shaped values that
// the live vocabulary holds are returned (`known`); anything else is dropped, never guessed.
const KEY = /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/;
export function stateServiceKeys(state: { specs?: Record<string, unknown> } | null | undefined, known?: Set<string>): string[] {
  const raw = state?.specs?.service_keys as unknown;
  const v = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as { value?: unknown }).value : raw;
  const parts = Array.isArray(v) ? v.map(String) : typeof v === 'string' ? v.split(/[\s,;|]+/) : [];
  return [...new Set(parts.map((s) => s.trim().toLowerCase()).filter((s) => KEY.test(s) && (!known || known.has(s))))].sort();
}
