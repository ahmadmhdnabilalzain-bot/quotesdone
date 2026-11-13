// customer_api — the quotation PDF for the Dropbox backup (it_engineer, 13 Nov 2026; founder ruling 1680). The door in index.ts
// authenticates the caller; this renders ONE live quote with buildQuotePdf (the portal's own quotation code) into backups/generated/.
import { isLiveQuote } from '../../_shared/quote_live.ts';
// deno-lint-ignore no-explicit-any
export type BackupQuoteDeps = { load: (id: string) => Promise<{ q: any; inq: any } | null>;
  // deno-lint-ignore no-explicit-any
  build: (q: any, inq: any, lang: 'en' | 'ar', target: { bucket: string; folder: string }) => Promise<{ j: any; ref: string }> };

export async function quotationForBackup(quoteId: string, lang: 'en' | 'ar', deps: BackupQuoteDeps): Promise<{ status: number; body: Record<string, unknown> }> {
  if (!/^[0-9a-f-]{36}$/i.test(quoteId)) return { status: 400, body: { error: 'bad_request' } };
  const got = await deps.load(quoteId);
  if (!got) return { status: 404, body: { error: 'quote_not_found' } };
  if (!isLiveQuote(got.q.status)) return { status: 409, body: { error: 'not_a_live_quote' } };
  const { j, ref } = await deps.build(got.q, got.inq, lang, { bucket: 'backups', folder: 'generated' });
  // an Arabic copy held for translation, or an unread reveal rate: no file, the row retries
  if (!j?.ok || !j.path) return { status: 503, body: { error: String(j?.error || (j?.held ? 'held' : 'pdf_failed')) } };
  return { status: 200, body: { ok: true, bucket: String(j.bucket || 'backups'), path: String(j.path), ref } };
}
