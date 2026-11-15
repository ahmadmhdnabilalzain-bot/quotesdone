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
import { siteNotes, type SitePhotos } from '../_shared/site_photos.ts';

export const PHOTOS_TITLE = 'Photos from the site';
export const VISIT_LINE = 'A final price may still need a site visit.';

export interface SitePhotosSection { title: string; urls: string[]; provided: string[]; not_provided: string[]; text: string }

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
  return { title: PHOTOS_TITLE, urls, provided: n.provided, not_provided: n.not_provided, text: parts.join(' ') };
}

/** One line for a notice (e-mail): said when the job needs a visit (shots were asked) or photos were sent. The notice never carries
 *  a photo: the checked copies are on the inquiry in the portal, and only once the check released them. '' when neither. */
export function photosLine(record: SitePhotos | null | undefined): string {
  if (!record || (!record.asked?.length && !record.photos?.length)) return '';
  const n = record.photos?.length ?? 0;
  return (n ? ` ${PHOTOS_TITLE}: the customer sent ${n} photo${n === 1 ? '' : 's'}; the checked copies are shown on the inquiry in the portal.` : '') + ' ' + VISIT_LINE;
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
    for (const j of data) {
      const res = j?.result ?? {};
      const ok = j?.why === 'site_photo_check' && j?.status === 'done' && res.redaction_complete === true && ['released', 'masked'].includes(String(res.photo?.status))
        && Array.isArray(res.drawing_redacted_paths) && res.drawing_redacted_paths.length === 1;
      if (ok && String(j.customer_id ?? '') === ownerOfJob.get(String(j.id))) paths.set(String(j.id), String(res.drawing_redacted_paths[0]));
    }
  } catch (_e) { /* fail closed: no photo */ }
  return { records, paths };
}
