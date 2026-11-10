// accountant — reading an inbound email as text (pickBody, over stripHtml) and a Dropbox-safe file name (dbxSafe).
// Moved here verbatim from index.ts on 9 Nov 2026 (the 1,715-line index.ts split into modules, a pure move).

// deno-lint-ignore no-explicit-any
function stripHtml(x: unknown) { return String(x || '').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&#36;/g, '$').replace(/\s+/g, ' ').trim(); }
// deno-lint-ignore no-explicit-any
export function pickBody(d: any) { const t = d?.text || d?.plain || d?.['body-plain'] || d?.['stripped-text'] || ''; const h = d?.html || d?.['body-html'] || ''; const b = String(t || ''); return b || (h ? stripHtml(h) : ''); }
export const dbxSafe = (x: string) => String(x || '').replace(/[\\/:*?"<>|\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
