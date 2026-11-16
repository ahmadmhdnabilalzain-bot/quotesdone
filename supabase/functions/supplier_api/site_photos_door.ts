// site_photos_door — "PHOTOS FROM THE SITE" ON EVERY SUPPLIER DOOR, AS CHECKED COPIES ONLY (15 Nov 2026, sales_engineer; founder
// ledger 1704: photos make it easier for suppliers to quote; ruling 1683: nothing reaches a supplier that names the customer).
//
// The inquiry holds the record (inquiries.spec.site_photos, _shared/site_photos.ts): the shots asked and each photo by its CHECK
// JOB. A supplier never receives the record (it is a customer-only key, _shared/site_location.ts) nor an original: this door reads
// the jobs, keeps only those the worker's check RELEASED or MASKED and recorded (cad_read_jobs.result.redaction_complete and its
// drawing_redacted_paths), and signs those paths through _shared/drawing_pages.ts signRedactedDrawings, which signs only a path
// recorded in drawing_redaction_runs. A photo still checking, withheld, or not recorded is simply not there.
// The section says which shots exist and which do not, and keeps the line that a final price may need a visit.
// Readers: supplier_api inbox (and through its row the inquiry PDF), the new-inquiry e-mail (customer_api matching.ts photosLine).
// prevented by: supplier_api/site_photos_door.test.ts
import { forSpec, siteNotes, withPhotos, type SitePhotos } from '../_shared/site_photos.ts';

export const PHOTOS_TITLE = 'Photos from the site';
export const VISIT_LINE = 'A final price may still need a site visit.';

export interface SitePhotosSection { title: string; urls: string[]; provided: string[]; not_provided: string[]; text: string;
  /** the same shots in Arabic (the asked shot's shot_ar), for the Arabic inquiry PDF */
  provided_ar: string[]; not_provided_ar: string[] }

/** The section a supplier reads, from the record and the signed URLs of the released copies (by job id). null = nothing asked
 *  and nothing sent. */
export function sitePhotosSection(record: SitePhotos | null | undefined, signed: Map<string, string>): SitePhotosSection | null {
  if (!record || (!record.asked?.length && !record.photos?.length)) return null;
  const released = new Set([...signed.keys()]);
  const n = siteNotes(record, released);
  const urls = (record.photos ?? []).map((p) => signed.get(p.job_id)).filter((u): u is string => !!u);
  const parts = [urls.length ? `${urls.length} checked photo${urls.length === 1 ? '' : 's'} from the customer` + (n.provided.length ? `, showing: ${n.provided.join('; ')}.` : '.') : 'No photo from the customer.'];
  if (n.not_provided.length) parts.push(`Not provided: ${n.not_provided.join('; ')}.`);
  parts.push(VISIT_LINE);
  const ar = (shot: string) => record.asked?.find((a) => a.shot === shot)?.shot_ar || shot;
  return { title: PHOTOS_TITLE, urls, provided: n.provided, not_provided: n.not_provided, text: parts.join(' '), provided_ar: n.provided.map(ar), not_provided_ar: n.not_provided.map(ar) };
}

/** One line for a notice (e-mail), TRUE when it is sent (review of bf8b9ea45, item 3): it counts only the copies the check has
 *  RELEASED (or masked) by then, and says plainly that photos still being checked appear on the inquiry once they clear. A
 *  withheld photo is not counted and not mentioned. The notice never carries a photo. '' when nothing was asked or sent. */
export function photosLine(record: SitePhotos | null | undefined, state: { released: number; checking: number } = { released: 0, checking: 0 }): string {
  if (!record || (!record.asked?.length && !record.photos?.length)) return '';
  const { released: n, checking: c } = state;
  const shown = n ? ` ${PHOTOS_TITLE}: ${n} checked photo${n === 1 ? '' : 's'} from the customer ${n === 1 ? 'is' : 'are'} shown on the inquiry in the portal.` : '';
  const later = c ? (n ? ` ${c === 1 ? 'One more is' : c + ' more are'} being checked and will be added there if cleared.` : ` ${PHOTOS_TITLE}: the customer's photos are being checked; any that clear are shown on the inquiry in the portal.`) : '';
  return shown + later + ' ' + VISIT_LINE;
}

/** A photo check job whose copy a supplier may see: the photo kind, done, released or masked, recorded complete with one copy. */
// deno-lint-ignore no-explicit-any
export function releasedJob(j: any): boolean {
  const res = j?.result ?? {};
  return j?.why === 'site_photo_check' && j?.status === 'done' && res.redaction_complete === true && ['released', 'masked'].includes(String(res.photo?.status))
    && Array.isArray(res.drawing_redacted_paths) && res.drawing_redacted_paths.length === 1;
}

// deno-lint-ignore no-explicit-any
type Admin = any;
/** The photo records of these inquiries and the released copy paths by job id. The record is read from inquiries.spec itself
 *  (inquiries_supplier_safe serves a masked spec that does not carry it), under the service role, for the ids this supplier's door
 *  already resolved. A job counts only when it is the inquiry's own customer's, of the photo kind, done, released or masked, and
 *  recorded complete with one copy. Unreadable = none (fail closed). */
export async function releasedSitePhotos(admin: Admin, ids: unknown[]): Promise<{ records: Map<string, SitePhotos>; paths: Map<string, string> }> {
  const records = new Map<string, SitePhotos>(), paths = new Map<string, string>();
  const want = [...new Set(ids.map(String).filter(Boolean))].slice(0, 100);
  if (!want.length) return { records, paths };
  try {
    const { data: inq, error: e1 } = await admin.from('inquiries').select('id,customer_id,site_photos:spec->site_photos').in('id', want);
    if (e1 || !Array.isArray(inq)) return { records, paths };
    const ownerOfJob = new Map<string, string>();
    for (const r of inq) {
      const rec = r?.site_photos as SitePhotos | null;
      if (!rec || typeof rec !== 'object' || !Array.isArray(rec.asked)) continue;
      records.set(String(r.id), rec);
      for (const p of Array.isArray(rec.photos) ? rec.photos : []) if (p?.job_id) ownerOfJob.set(String(p.job_id), String(r.customer_id ?? ''));
    }
    if (!ownerOfJob.size) return { records, paths };
    const { data, error } = await admin.from('cad_read_jobs').select('id,customer_id,why,status,result').in('id', [...ownerOfJob.keys()].slice(0, 200));
    if (error || !Array.isArray(data)) return { records, paths };
    for (const j of data) if (releasedJob(j) && String(j.customer_id ?? '') === ownerOfJob.get(String(j.id))) paths.set(String(j.id), String(j.result.drawing_redacted_paths[0]));
  } catch (_e) { /* fail closed: no photo */ }
  return { records, paths };
}

/** At create time (the new-inquiry e-mail): of this customer's photo jobs on the record, how many are released and how many are
 *  still being checked (queued or running). Unreadable = none of either (the line then says only the visit line). */
export async function photoStates(admin: Admin, customerId: string, record: SitePhotos | null | undefined): Promise<{ released: number; checking: number }> {
  const ids = [...new Set((record?.photos ?? []).map((p) => String(p?.job_id || '')).filter(Boolean))].slice(0, 50);
  if (!ids.length) return { released: 0, checking: 0 };
  try {
    const { data, error } = await admin.from('cad_read_jobs').select('id,customer_id,why,status,result').in('id', ids).eq('customer_id', customerId);
    if (error || !Array.isArray(data)) return { released: 0, checking: 0 };
    return { released: data.filter(releasedJob).length, checking: data.filter((j) => j?.why === 'site_photo_check' && ['queued', 'running'].includes(String(j.status))).length };
  } catch (_e) { return { released: 0, checking: 0 }; }
}

/** The photos create_inquiry keeps: the intake's record, plus the jobs the portal sends with Send (a photo uploaded after the last
 *  chat turn whose record could not be written), each kept only when it is this customer's own photo check job (review item 2). */
export async function photosAtSend(admin: Admin, customerId: string, record: SitePhotos | null, sent: unknown): Promise<SitePhotos | null> {
  const want = (Array.isArray(sent) ? sent : []).map((x) => ({ job_id: String((x as { job_id?: unknown })?.job_id ?? '').toLowerCase(), shot: (x as { shot?: unknown })?.shot ?? null }))
    .filter((x) => /^[0-9a-f-]{36}$/.test(x.job_id) && !(record?.photos ?? []).some((p) => p.job_id === x.job_id)).slice(0, 12);
  let mine: { job_id: string; shot: unknown }[] = [];
  if (want.length) {
    try {
      const { data, error } = await admin.from('cad_read_jobs').select('id').in('id', want.map((x) => x.job_id)).eq('customer_id', customerId).eq('why', 'site_photo_check');
      const own = new Set((error || !Array.isArray(data) ? [] : data).map((j: { id: unknown }) => String(j.id).toLowerCase()));
      mine = want.filter((x) => own.has(x.job_id));
    } catch (_e) { mine = []; }
  }
  if (!record && !mine.length) return null;
  return forSpec(withPhotos(record ?? { asked: [], photos: [] }, [], mine, 'portal'));
}
