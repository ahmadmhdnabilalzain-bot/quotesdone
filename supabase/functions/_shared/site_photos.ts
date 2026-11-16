// site_photos — A JOB THAT NEEDS A SITE VISIT ASKS ONCE FOR THE PHOTOS THAT LET A SUPPLIER PRICE WITHOUT ONE (15 Nov 2026,
// sales_engineer; founder ledger 1704, verbatim: "For stuff that requires a site visit. The sales engineer should ask for photos.
// It will make it easier for suppliers to quote.").
//
// THE RULES, all pure so they are tested offline (inquiry_intake/a_site_visit_job_asks_once_for_photos.test.ts):
//   * WHEN: the model judged a trade's site-visit condition applies to this job (it put the trade in "site_visit"), and that
//     trade's job checklist carries photos_to_ask (scripts/kb/photos_to_ask.mjs, read off the pack's own site-visit sentence).
//   * ONCE: the assistant turn that asks is stamped `photo_ask` (the shots), and the request's site_photos record keeps `asked`;
//     either one means it is never asked again, whatever the customer answers or does not answer (the never-ask-twice rules
//     of #2007 count spec asks, asked_keys; a photo ask is not a spec and never enters them, so it can never hold a request).
//   * OPTIONAL: nothing here touches status or readiness. "No photos", silence, or photos of only some shots never blocks Send.
//   * THE BRIEF TELLS SUPPLIERS which shots exist and which do not (siteNotes): received shots, shots not provided, and the line
//     that a final price may need a visit.
//   * A PHOTO REACHES A SUPPLIER ONLY AS ITS CHECKED COPY (founder ruling 1683): a photo is recorded here by its check job
//     (cad_read_jobs, why 'site_photo_check', _shared/site_photo_gate.ts on the worker); the supplier door shows only a copy
//     that job released and recorded, never the original (supplier_api/what_a_supplier_receives.ts supplierSitePhotos).
import { activeChecklists, type PhotoShot, type TradeContext } from './inquiry_trades.ts';

/** One shot asked of this request: the checklist's shot, and the trade and checklist it came from. */
export interface AskedShot extends PhotoShot { trade: string; topic_id: string }
/** One photo the customer sent: the shot it answers (null when sent without one, as on WhatsApp), its check job, the door. */
export interface SitePhoto { shot: string | null; job_id: string; via: 'portal' | 'whatsapp' }
/** What the request holds about photos. `asked` empty = never asked. */
export interface SitePhotos { asked: AskedShot[]; photos: SitePhoto[]; declined?: boolean }

/** At most this many shots are asked, across every trade the visit applies to (one message, one list). */
export const MAX_ASKED = 6;
/** At most this many photos are kept per request (the check runs on the worker, one job each). */
export const MAX_PHOTOS = 12;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The shots for the trades whose site visit applies: each trade's job checklist(s), in the model's trade order, deduplicated. */
export function shotsFor(ctx: TradeContext | null, topics: string[], siteVisit: string[]): AskedShot[] {
  const out: AskedShot[] = [];
  const seen = new Set<string>();
  const active = activeChecklists(ctx, topics);
  for (const code of ctx?.codes ?? []) {
    if (!siteVisit.includes(code)) continue;
    for (const c of active[code] ?? []) for (const p of c.photos ?? []) {
      if (!c.site_visit_required_when || !p.shot || seen.has(p.shot.toLowerCase())) continue;
      seen.add(p.shot.toLowerCase());
      out.push({ ...p, trade: code, topic_id: c.topic_id });
    }
  }
  return out.slice(0, MAX_ASKED);
}

/** True when any assistant turn of this conversation already asked for photos (the stamp), or the record says so. */
// deno-lint-ignore no-explicit-any
export function askedBefore(turns: any[], record: SitePhotos | null | undefined): boolean {
  if (record && Array.isArray(record.asked) && record.asked.length) return true;
  return (Array.isArray(turns) ? turns : []).some((t) => t && t.role === 'assistant' && Array.isArray(t.photo_ask) && t.photo_ask.length > 0);
}

/** The shots to ask on THIS turn, or [] when the ask is not due (no visit applies, no shots, or already asked). */
// deno-lint-ignore no-explicit-any
export function photoAskNow(ctx: TradeContext | null, topics: string[], siteVisit: string[], turns: any[], record: SitePhotos | null | undefined): AskedShot[] {
  if (!siteVisit.length || askedBefore(turns, record)) return [];
  return shotsFor(ctx, topics, siteVisit);
}

/** THE ASK OF THIS TURN (review of bf8b9ea45, item 7). Due when a visit applies (photoAskNow): `draft` is true when the model's own
 *  reply did not ask, so code adds the list. And when the model ASKED on its own (photos_asked true) on a turn where it put no
 *  trade in site_visit, the turn is stamped too, with the shots of every placed trade that has some, so the prompt block (shown
 *  until a stamp exists) never invites a second ask. [] when asked before or nothing to ask. */
// deno-lint-ignore no-explicit-any
export function photoAskOfTurn(ctx: TradeContext | null, topics: string[], siteVisit: string[], turns: any[], record: SitePhotos | null | undefined, modelAsked: boolean): { shots: AskedShot[]; draft: boolean } {
  if (askedBefore(turns, record)) return { shots: [], draft: false };
  const due = photoAskNow(ctx, topics, siteVisit, turns, record);
  if (due.length) return { shots: due, draft: !modelAsked };
  return modelAsked ? { shots: shotsFor(ctx, topics, ctx?.codes ?? []), draft: false } : { shots: [], draft: false };
}

/** The record of a request row: inquiry_intake.site_photos (its own column, written by fn_site_photos_record), else the copy an
 *  older turn kept inside brief. null when neither holds one. */
// deno-lint-ignore no-explicit-any
export function recordOf(row: any): SitePhotos | null {
  const own = row?.site_photos, old = row?.brief?.site_photos;
  for (const r of [own, old]) if (r && typeof r === 'object' && Array.isArray(r.asked)) return r as SitePhotos;
  return null;
}

/** The prompt block for the model: what to ask, once, when it judges a visit applies. '' when asked before or nothing to ask. */
// deno-lint-ignore no-explicit-any
export function photoPromptBlock(ctx: TradeContext | null, topics: string[], turns: any[], record: SitePhotos | null | undefined, lang: 'en' | 'ar' = 'en'): string {
  if (askedBefore(turns, record)) return '';
  const lines: string[] = [];
  const active = activeChecklists(ctx, topics);
  for (const code of ctx?.codes ?? []) for (const c of active[code] ?? []) {
    if (!c.site_visit_required_when || !(c.photos ?? []).length) continue;
    lines.push(`  [${code}] ${(c.photos ?? []).map((p) => (lang === 'ar' && p.shot_ar ? p.shot_ar : p.shot)).join('; ')}`);
  }
  if (!lines.length) return '';
  return 'PHOTOS FOR A SITE-VISIT JOB (founder ledger 1704): on the turn you put a trade in "site_visit", in that SAME reply say plainly that a final price may need a visit, and ask ONCE for these photos so the suppliers can price without one, as one short list in plain words. Say the photos are optional and the request can be sent without them. Set "photos_asked": true on that turn. Never ask for photos again after that turn, and never hold the request for them.\n' + lines.join('\n');
}

/** The ask, written by code only as a draft for the model to voice when its own reply did not ask (the voice step rewrites it). */
export function photoAskDraft(shots: AskedShot[], lang: 'en' | 'ar' = 'en'): string {
  if (!shots.length) return '';
  const list = shots.map((s) => (lang === 'ar' && s.shot_ar ? s.shot_ar : s.shot)).join('؛ ');
  return lang === 'ar'
    ? `قد يحتاج السعر النهائي إلى زيارة للموقع. إن أمكن، أرفق هذه الصور ليتمكن الموردون من التسعير دون زيارة: ${list}. الصور اختيارية، ويمكنك إرسال الطلب بدونها.`
    : `A final price may need a site visit. If you can, attach these photos so the suppliers can price without one: ${shots.map((s) => s.shot).join('; ')}. Photos are optional: you can send the request without them.`;
}

/** The record with this turn's ask and photos added. Photos are kept by check job (a retry never adds one twice), at most MAX_PHOTOS;
 *  a shot is kept only when it is one of the asked shots (else null: "sent without a shot"). */
export function withPhotos(prev: SitePhotos | null | undefined, askedNow: AskedShot[], incoming: unknown, via: 'portal' | 'whatsapp' = 'portal', declined = false): SitePhotos {
  const asked = prev && Array.isArray(prev.asked) && prev.asked.length ? prev.asked : askedNow;
  const shots = new Set(asked.map((a) => a.shot));
  const photos: SitePhoto[] = Array.isArray(prev?.photos) ? [...prev!.photos] : [];
  for (const x of Array.isArray(incoming) ? incoming : []) {
    const job = String((x as { job_id?: unknown })?.job_id ?? '').trim();
    if (!UUID.test(job) || photos.some((p) => p.job_id === job) || photos.length >= MAX_PHOTOS) continue;
    const shot = String((x as { shot?: unknown })?.shot ?? '').trim();
    photos.push({ shot: shots.has(shot) ? shot : null, job_id: job, via });
  }
  return { asked, photos, ...(prev?.declined || declined ? { declined: true } : {}) };
}

/** What the suppliers are told about the photos, from the record and the copies the check released (job id -> released). */
export function siteNotes(record: SitePhotos | null | undefined, released: Set<string> = new Set()): { provided: string[]; not_provided: string[]; extra: number; withheld: number } {
  const asked = record?.asked ?? [];
  const ok = (record?.photos ?? []).filter((p) => released.has(p.job_id));
  const provided = asked.map((a) => a.shot).filter((s) => ok.some((p) => p.shot === s));
  return { provided, not_provided: asked.map((a) => a.shot).filter((s) => !provided.includes(s)), extra: ok.filter((p) => !p.shot || !asked.some((a) => a.shot === p.shot)).length,
    withheld: (record?.photos ?? []).length - ok.length };
}

/** At most this many photos one customer may send for checking in 24 hours, across every request and door (the check is a
 *  worker job with OCR and up to PHOTO_LOOKS paid looks each; site_photo_gate.ts states the cost). */
export const PHOTOS_PER_DAY = 24;

// deno-lint-ignore no-explicit-any
type Admin = any;
/** How many photo checks this customer queued in the last 24 hours (null when it cannot be read: the caller refuses, fail closed). */
export async function photosToday(admin: Admin, customerId: string): Promise<number | null> {
  try {
    const { count, error } = await admin.from('cad_read_jobs').select('id', { count: 'exact', head: true }).eq('customer_id', customerId)
      .eq('why', 'site_photo_check').gte('created_at', new Date(Date.now() - 86_400_000).toISOString());
    return error ? null : Number(count ?? 0);
  } catch (_e) { return null; }
}

/** RECORD PHOTOS IN ONE STATEMENT (review of bf8b9ea45, items 2 and 4): public.fn_site_photos_record adds them to
 *  inquiry_intake.site_photos, or to inquiries.spec.site_photos with jsonb_set, computed from the row as it is under its lock,
 *  so two photos sent together both stay and a chat turn saved meanwhile is never overwritten (nor overwrites them). Each photo
 *  must be a site_photo_check job of the row's own customer; the database keeps them by job, at most MAX_PHOTOS, and keeps a
 *  shot only when it was asked. `asked` is set once and never replaced. Returns the record as stored, or null (no row of this
 *  customer, or the call failed: nothing recorded, never a partial record). */
export async function recordSitePhotos(admin: Admin, o: { table: 'inquiry_intake' | 'inquiries'; id: string; customerId: string; email?: string | null;
  photos?: { job_id: string; shot?: string | null }[]; via?: 'portal' | 'whatsapp'; asked?: AskedShot[] | null; declined?: boolean }): Promise<SitePhotos | null> {
  if (!UUID.test(String(o.id || '')) || !UUID.test(String(o.customerId || ''))) return null;
  try {
    const { data, error } = await admin.rpc('fn_site_photos_record', { p_table: o.table, p_id: o.id, p_customer_id: o.customerId, p_email: o.email ?? null,
      p_photos: (o.photos ?? []).map((p) => ({ job_id: String(p.job_id), shot: p.shot ?? null })), p_via: o.via ?? 'portal',
      p_asked: o.asked && o.asked.length ? o.asked : null, p_declined: o.declined === true });
    if (error || !data || typeof data !== 'object' || !Array.isArray((data as SitePhotos).asked)) return null;
    return data as SitePhotos;
  } catch (_e) { return null; }
}

/** The record as create_inquiry stores it on inquiries.spec.site_photos (kept apart from the details the text gate reads). */
export function forSpec(record: unknown): SitePhotos | null {
  const r = record as SitePhotos | null;
  if (!r || typeof r !== 'object' || !Array.isArray(r.asked)) return null;
  const clean = withPhotos({ asked: r.asked.filter((a) => a && typeof a.shot === 'string').slice(0, MAX_ASKED).map((a) => ({ shot: String(a.shot), shot_ar: String(a.shot_ar ?? ''), from: String(a.from ?? ''), trade: String(a.trade ?? ''), topic_id: String(a.topic_id ?? '') })), photos: [] },
    [], (Array.isArray(r.photos) ? r.photos : []), 'portal', r.declined === true);
  // the door each photo came by is kept as recorded
  clean.photos = clean.photos.map((p) => ({ ...p, via: (r.photos ?? []).find((q) => q?.job_id === p.job_id)?.via === 'whatsapp' ? 'whatsapp' : 'portal' }));
  return clean.asked.length || clean.photos.length ? clean : null;
}
