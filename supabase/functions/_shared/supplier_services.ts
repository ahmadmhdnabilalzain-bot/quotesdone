// THE SERVICES CHECKLIST — what a supplier says it does, as server actions (15 Sep 2026, sales_engineer).
//
// Founder, 15 Sep 2026: the Services tab "will be our cross matching main source", prepared by the
// sales engineer so the supplier ticks rather than types; and "later this will be a mobile app as
// well. the structure need to be built in already." So every step is a supplier_api action with a
// typed request and response (docs/api/supplier_portal_services.md) and the React tab is one client:
//
//   services_state          -> the prepared checklist, the vocabulary, what is saved, the voice switch
//   services_resolve        -> what one free-text service means: listed trade codes, or a new proposal
//   services_save           -> ticks + extras + roles, confirmed through capabilityConfirm (the ledger)
//   transcribe_service_note -> a recorded note to text, behind decision_policy supplier_voice_input_enabled
//
// WHERE IT LANDS FOR MATCHING. fn_match_capability gates on supplier_capabilities.trades +
// confirmed_at. A ticked service is stored in supplier_capabilities.services as '<trade>.<code>' and
// its trade is added to trades, so the checklist feeds the gate itself. A free-text service goes
// through public.fn_norm_trades (exact alias or nothing, never a neighbour): each code it names joins
// trades; text no alias names stays a service string and becomes a taxonomy_trade_proposal row that
// the sales engineer reviews. No model anywhere on this path.

import { capabilityConfirm, capabilityState, tradeCode } from './supplier_capability.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

export type ServiceRow = { trade_code: string; code: string; label_en: string; label_ar: string; sort?: number };
export type ChecklistService = { key: string; label_en: string; label_ar: string };
export type ChecklistTrade = {
  code: string; label_en: string; label_ar: string | null;
  source: 'confirmed' | 'on_file' | 'documents';
  services: ChecklistService[];
};
export type VoiceConfig = { enabled: boolean; max_seconds: number; max_bytes: number; mime: readonly string[] };

export const MAX_EXTRAS = 25;
export const EXTRA_LEN = 120;
// Voice limits. A 16 kHz mono 16-bit WAV is 32 KB a second, so 60 s is about 1.9 MB.
export const VOICE: Omit<VoiceConfig, 'enabled'> = { max_seconds: 60, max_bytes: 2_500_000, mime: ['audio/wav', 'audio/mpeg'] };
export const VOICE_PER_HOUR = 20;
export const VOICE_FLAG = 'supplier_voice_input_enabled';

export const serviceKey = (trade: string, code: string) => `${trade}.${code}`;

/** A stored services array split into checklist keys we know and the supplier's own words. */
export function splitServices(stored: unknown, known: Set<string>): { selected: string[]; extras: string[] } {
  const selected: string[] = []; const extras: string[] = [];
  for (const raw of Array.isArray(stored) ? stored : []) {
    const s = String(raw ?? '').trim();
    if (!s) continue;
    // A key-shaped string we do not list (a retired service, or words the supplier typed that look like
    // 'a.b') is kept as the supplier's own words rather than dropped on the next load.
    if (known.has(s)) selected.push(s); else extras.push(s);
  }
  return { selected: [...new Set(selected)], extras: [...new Set(extras)] };
}

/** Trimmed, de-duplicated (case-insensitive), clipped free-text services. */
export function cleanExtras(v: unknown): string[] {
  const out: string[] = []; const seen = new Set<string>();
  for (const raw of Array.isArray(v) ? v : []) {
    const s = String(raw ?? '').replace(/\s+/g, ' ').trim().slice(0, EXTRA_LEN);
    const k = s.toLowerCase();
    if (s.length < 2 || seen.has(k)) continue;
    seen.add(k); out.push(s);
    if (out.length >= MAX_EXTRAS) break;
  }
  return out;
}

/** 'ar' when the text carries Arabic letters, 'en' when it carries anything else, '' when empty. */
export const langOf = (text: string): '' | 'ar' | 'en' => !text.trim() ? '' : /[؀-ۿ]/.test(text) ? 'ar' : 'en';

/** Which trades the checklist opens with, and why. Confirmed wins; before a confirm it is what we
 *  hold on file plus what the supplier's own documents name (supplier_doc_trades.ts). */
export function preparedTrades(cap: Record<string, unknown> | null, confirmed: boolean): { code: string; source: ChecklistTrade['source'] }[] {
  const held = Array.isArray(cap?.trades) ? (cap!.trades as string[]) : [];
  if (confirmed) return held.map((code) => ({ code, source: 'confirmed' as const }));
  const docs = Array.isArray(cap?.proposed_trades) ? (cap!.proposed_trades as string[]) : [];
  const out: { code: string; source: ChecklistTrade['source'] }[] = held.map((code) => ({ code, source: 'on_file' }));
  for (const code of docs) if (!held.includes(code)) out.push({ code, source: 'documents' });
  return out;
}

async function serviceRows(admin: Admin): Promise<ServiceRow[]> {
  const { data, error } = await admin.from('taxonomy_trade_service')
    .select('trade_code,code,label_en,label_ar,sort').eq('active', true).order('trade_code').order('sort');
  return error ? [] : (data || []);
}

export async function voiceEnabled(admin: Admin): Promise<boolean> {
  const { data } = await admin.from('decision_policy').select('value').eq('key', VOICE_FLAG).maybeSingle();
  const v = data?.value;
  return v === true || (!!v && typeof v === 'object' && (v as { enabled?: unknown }).enabled === true);
}

export async function servicesState(admin: Admin, supplierId: number) {
  const base = await capabilityState(admin, supplierId);
  const rows = await serviceRows(admin);
  const byTrade: Record<string, ChecklistService[]> = {};
  for (const r of rows) (byTrade[r.trade_code] ||= []).push({ key: serviceKey(r.trade_code, r.code), label_en: r.label_en, label_ar: r.label_ar });
  const known = new Set(rows.map((r) => serviceKey(r.trade_code, r.code)));
  const cap = base.capability as Record<string, unknown> | null;
  const { selected, extras } = splitServices(cap?.services, known);
  const vocab = base.vocabulary.trades as { code: string; label: string; label_ar?: string | null }[];
  const labelOf = (code: string) => vocab.find((t) => t.code === code);
  const prepared = preparedTrades(cap, base.confirmed);
  // FIRST RUN IS PRE-TICKED. Before any confirm, and while nothing was ever chosen, every service of
  // every prepared trade is ticked: the sales engineer's proposal, which the supplier corrects.
  const firstRun = !base.confirmed && selected.length === 0;
  const checklist: ChecklistTrade[] = prepared.map(({ code, source }) => {
    const t = labelOf(code);
    return { code, source, label_en: t?.label || code.replace(/_/g, ' '), label_ar: t?.label_ar ?? null, services: byTrade[code] || [] };
  });
  const ticked = firstRun ? checklist.flatMap((t) => t.services.map((s) => s.key)) : selected;
  return {
    ok: true, confirmed: base.confirmed, first_run: firstRun,
    capability: cap, history: base.history, vocabulary: base.vocabulary, trade_proposals: base.trade_proposals,
    services_by_trade: byTrade, checklist,
    selected_services: ticked, extra_services: extras,
    voice: { enabled: await voiceEnabled(admin), ...VOICE } as VoiceConfig,
  };
}

/** Codes fn_norm_trades names in the text (exact alias or nothing). */
export async function resolveText(admin: Admin, text: string): Promise<string[]> {
  const { data, error } = await admin.rpc('fn_norm_trades', { p_text: text });
  return error || !Array.isArray(data) ? [] : data.map(String);
}

export async function servicesResolve(admin: Admin, body: Record<string, unknown>): Promise<[number, Record<string, unknown>]> {
  const text = cleanExtras([body.text])[0];
  if (!text) return [400, { error: 'empty_text', code: 'services_empty_text' }];
  const trades = await resolveText(admin, text);
  return [200, { ok: true, text, trades, new_trade: trades.length ? null : tradeCode(text) }];
}

/** Save the checklist. Returns [status, body]; the confirm itself is capabilityConfirm, unchanged. */
export async function servicesSave(admin: Admin, supplierId: number, body: Record<string, unknown>, declaredEmirates: string[] = []): Promise<[number, Record<string, unknown>]> {
  const rows = await serviceRows(admin);
  const known = new Set(rows.map((r) => serviceKey(r.trade_code, r.code)));
  const keys = [...new Set((Array.isArray(body.services) ? body.services : []).map((s) => String(s ?? '')).filter((s) => known.has(s)))];
  const extras = cleanExtras(body.extra_services);
  const trades = new Set((Array.isArray(body.trades) ? body.trades : []).map((t) => String(t ?? '').trim()).filter(Boolean).slice(0, 25));
  // A ticked service means its trade.
  for (const k of keys) trades.add(k.split('.')[0]);
  const resolved: Record<string, string[]> = {}; const proposals: string[] = [];
  for (const e of extras) {
    const codes = await resolveText(admin, e);
    resolved[e] = codes;
    if (codes.length) codes.forEach((c) => trades.add(c)); else proposals.push(e);
  }
  const { data: cap } = await admin.from('supplier_capabilities')
    .select('products_norm,coverage_emirates,brands,project_types,exclusions').eq('supplier_id', supplierId).maybeSingle();
  const coverage = Array.isArray(cap?.coverage_emirates) && cap.coverage_emirates.length ? cap.coverage_emirates : declaredEmirates;
  const [status, out] = await capabilityConfirm(admin, supplierId, {
    trades: [...trades], roles: body.roles,
    services: [...keys, ...extras],
    products: cap?.products_norm || [], coverage_emirates: coverage || [],
    brands: cap?.brands || [], project_types: cap?.project_types || [], exclusions: cap?.exclusions || [],
  });
  if (status !== 200) return [status, out];
  // Free text no alias names: kept as the supplier's service AND sent to the sales engineer as a
  // possible new trade (the open list, founder 14 Sep 2026). ignoreDuplicates keeps a decided row.
  const fresh = proposals.map((p) => ({ raw: p, code: tradeCode(p) })).filter((p) => p.code);
  if (fresh.length) {
    await admin.from('taxonomy_trade_proposal').upsert(fresh.map(({ raw, code }) => {
      const ar = langOf(raw) === 'ar';
      return { supplier_id: supplierId, code, label_en: ar ? null : raw, label_ar: ar ? raw : null, note: 'services checklist: free-text service' };
    }), { onConflict: 'supplier_id,code', ignoreDuplicates: true });
  }
  return [200, { ...out, services: keys, extra_services: extras, resolved, proposed_trades: fresh.map((p) => p.code) }];
}

// ── VOICE ─────────────────────────────────────────────────────────────────────────────────────────
// THE LIMIT RESERVES BEFORE IT COUNTS (database review, 15 Sep 2026). Count-then-insert let parallel
// requests all read 19 and all pass; each request now writes its 'pending' audit row first and then
// counts the hour INCLUDING itself, so concurrent requests see one another and the cap cannot be
// overshot (at worst a burst admits fewer than 20).
export type VoiceDeps = {
  enabled: () => Promise<boolean>;
  recentCount: (supplierId: number) => Promise<number>;          // admitted-or-pending requests in the last hour, own row included
  audit: (row: Record<string, unknown>) => Promise<void>;        // a finished row (flag_off)
  start: (row: Record<string, unknown>) => Promise<(patch: Record<string, unknown>) => Promise<void>>;  // pending row -> finisher
  transcribe: (b64: string, mime: string) => Promise<{ ok: true; text: string } | { ok: false; error: string }>;
};

/** Decoded size of a base64 string, without decoding it. */
export const b64Bytes = (b64: string) => Math.floor(b64.length * 3 / 4) - (b64.endsWith('==') ? 2 : b64.endsWith('=') ? 1 : 0);

export function checkVoice(body: Record<string, unknown>): { ok: true; b64: string; mime: string; bytes: number; duration: number | null } | { ok: false; code: string; status: number } {
  const b64 = String(body.audio_b64 || '').replace(/^data:[^,]*,/, '');
  const mime = String(body.mime || '').toLowerCase().split(';')[0].trim();
  const d = Number(body.duration_ms);
  const duration = Number.isFinite(d) && d >= 0 ? Math.round(d) : null;
  if (!VOICE.mime.includes(mime)) return { ok: false, code: 'voice_bad_type', status: 415 };
  if (b64.length < 100 || !/^[A-Za-z0-9+/=\s]+$/.test(b64.slice(0, 4096))) return { ok: false, code: 'voice_empty', status: 400 };
  const bytes = b64Bytes(b64.replace(/\s+/g, ''));
  if (bytes > VOICE.max_bytes) return { ok: false, code: 'voice_too_large', status: 413 };
  if (duration !== null && duration > VOICE.max_seconds * 1000 + 1500) return { ok: false, code: 'voice_too_long', status: 413 };
  return { ok: true, b64, mime, bytes, duration };
}

/** One voice note to text. Every call leaves exactly one audit row; none holds audio or text. */
export async function transcribeServiceNote(supplierId: number, body: Record<string, unknown>, deps: VoiceDeps): Promise<[number, Record<string, unknown>]> {
  const base = { supplier_id: supplierId, bytes: 0, duration_ms: null as number | null, mime: null as string | null };
  if (!(await deps.enabled())) {
    await deps.audit({ ...base, outcome: 'flag_off' });
    return [503, { ok: false, code: 'voice_input_off', error: 'voice_input_off' }];
  }
  const v = checkVoice(body);
  const finish = await deps.start(v.ok ? { ...base, bytes: v.bytes, duration_ms: v.duration, mime: v.mime, outcome: 'pending' } : { ...base, outcome: 'pending' });
  if ((await deps.recentCount(supplierId)) > VOICE_PER_HOUR) {
    await finish({ outcome: 'rate_limited' });
    return [429, { ok: false, code: 'voice_rate_limited', error: 'voice_rate_limited', per_hour: VOICE_PER_HOUR }];
  }
  if (!v.ok) {
    await finish({ outcome: 'refused' });
    return [v.status, { ok: false, code: v.code, error: v.code }];
  }
  const r = await deps.transcribe(v.b64, v.mime);
  if (!r.ok) {
    await finish({ outcome: 'failed' });
    return [502, { ok: false, code: 'voice_failed', error: 'voice_failed' }];
  }
  const text = r.text.trim();
  const lang = langOf(text);
  await finish({ outcome: text ? 'transcribed' : 'empty', lang: lang || null, chars: text.length });
  return [200, { ok: true, text, lang }];
}
