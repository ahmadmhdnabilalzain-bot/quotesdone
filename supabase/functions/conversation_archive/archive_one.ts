// One message into the archive (it_engineer, 2 Nov 2026; review of #1797). Every conversation is kept (founder, 14 Sep
// 2026), so a message the PDF renderer cannot draw inside the edge's CPU cap must not stay pending for ever: the attempt
// is counted BEFORE the render (a worker the cap kills has still counted), and from the attempt after
// ATTEMPTS_BEFORE_COPY the message is kept as its HTML copy instead (document.ts conversationHtml), recorded like a PDF
// and named in an it_engineer finding. A counter that cannot be read (the table not yet applied) means "draw the PDF",
// exactly the behaviour before this file. prevented by: conversation_archive/archive_one.test.ts
import { ATTEMPTS_BEFORE_COPY, conversationHtml, type ConversationRow } from './document.ts';

export type Rendered = { ok: true; bytes: Uint8Array } | { ok: false; error: string };
export interface ArchiveDeps {
  attempt(r: ConversationRow): Promise<number | null>;
  render(r: ConversationRow): Promise<Rendered>;
  upload(path: string, bytes: Uint8Array, contentType: string): Promise<string | null>;   // the error, or null
  record(r: ConversationRow, path: string, bytes: number): Promise<{ ok: boolean; queued: number; error?: string }>;
  clear(r: ConversationRow): Promise<void>;
  finding(r: ConversationRow, attempts: number, path: string): Promise<void>;
}
export type Archived = { ok: true; light: boolean; queued: number; path: string } | { ok: false; error: string };

export const archivePath = (r: ConversationRow, ext: 'pdf' | 'html') =>
  `conversations/${r.channel}/${String(r.occurred_at || new Date().toISOString()).slice(0, 7)}/${r.source_table}-${r.source_id}.${ext}`;

export async function archiveOne(r: ConversationRow, d: ArchiveDeps): Promise<Archived> {
  const attempts = await d.attempt(r).catch(() => null);
  const light = attempts !== null && attempts > ATTEMPTS_BEFORE_COPY;
  let bytes: Uint8Array;
  if (light) bytes = new TextEncoder().encode(conversationHtml(r));
  else {
    const out = await d.render(r);
    if (!out.ok) return { ok: false, error: 'render ' + out.error };
    bytes = out.bytes;
  }
  const path = archivePath(r, light ? 'html' : 'pdf');
  const upErr = await d.upload(path, bytes, light ? 'text/html; charset=utf-8' : 'application/pdf');
  if (upErr) return { ok: false, error: 'upload ' + upErr };
  const rec = await d.record(r, path, bytes.length);
  if (!rec.ok) return { ok: false, error: 'record ' + (rec.error || 'refused') };
  await d.clear(r).catch(() => {});
  if (light) await d.finding(r, attempts!, path).catch(() => {});
  return { ok: true, light, queued: rec.queued, path };
}
