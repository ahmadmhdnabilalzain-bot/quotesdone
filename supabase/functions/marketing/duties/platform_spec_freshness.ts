// Platform spec freshness (split out of duties.ts, 9 Nov 2026; a pure move).
import { sha256 } from './shared.ts';
import type { Duty } from './types.ts';

// A page's VISIBLE text, so a rotated script nonce or tracking tag is not a "change" — only the words are.
export function visibleText(html: string): string {
  return html.replace(/<(script|style|noscript)[\s\S]*?<\/\1>/gi, ' ').replace(/<[^>]+>/g, ' ')
    // Google's help pages carry a fresh random 10+ digit token on every load; it is not a word of the page.
    .replace(/&[a-z#0-9]+;/gi, ' ').replace(/\b\d{10,}\b/g, ' ').replace(/\s+/g, ' ').trim();
}
/** What a source is hashed on. A Postiz provider file (raw.githubusercontent.com/gitroomhq/postiz-app) changes with nearly every
 *  upstream commit, but the platform_spec rows cite only its maxLength() (9 Nov 2026: four such sources kept 13 findings
 *  open and re-raised ~640 times). Those files are hashed on the body of maxLength() alone, comments and whitespace removed;
 *  a file with no maxLength() hashes as a fixed marker, so a refactor that removes it still shows as one change. Every other
 *  page is hashed on its visible text, as before. */
export function specHashText(url: string, body: string): string {
  if (!/^https:\/\/raw\.githubusercontent\.com\/gitroomhq\/postiz-app\//.test(url)) return visibleText(body);
  const at = body.search(/^[ \t]*(?:override\s+)?maxLength\s*\(/m);
  if (at < 0) return 'postiz: no maxLength() in this file';
  const open = body.indexOf('{', body.indexOf(')', at));
  if (open < 0) return 'postiz: no maxLength() in this file';
  let depth = 0, end = -1;
  for (let i = open; i < body.length; i++) {
    if (body[i] === '{') depth++;
    else if (body[i] === '}' && --depth === 0) { end = i; break; }
  }
  const method = end < 0 ? body.slice(at) : body.slice(at, end + 1);
  return method.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ').replace(/\s+/g, ' ').trim();
}

// PLATFORM SPEC FRESHNESS (founder instruction 869, 23 Sep 2026). Every page marketing_platform_spec cites is re-read
// once a month, three per beat (the edge CPU cap). A changed page, or one that stops answering, is an IT finding owned
// by marketing (fn_marketing_platform_spec_freshness -> fn_it_duty_settle 'marketing_platform_spec_freshness') and it
// stays open until the rows are re-checked and fn_marketing_platform_spec_source_verified(url, who) is called.
export const platformSpecFreshness: Duty = {
  name: 'platform_spec_freshness',
  owner_seat: 'marketing',
  run: async ({ admin }) => {
    const due = await admin.rpc('fn_marketing_platform_spec_sources_due', { p_limit: 3 });
    if (due.error) throw new Error('sources_due: ' + due.error.message);
    const urls = (due.data || []) as string[];
    let changed = 0;
    for (const url of urls) {
      let hash: string | null = null, status = 0, error: string | null = null;
      try {
        const r = await fetch(url, { headers: { 'User-Agent': 'QuotesDone-marketing-spec-check' }, signal: AbortSignal.timeout(12000) });
        status = r.status;
        if (r.ok) hash = await sha256(specHashText(url, await r.text()));
        else error = 'HTTP ' + r.status;
      } catch (e) { error = String((e as Error)?.message || e); }
      const seen = await admin.rpc('fn_marketing_platform_spec_source_seen', { p_url: url, p_hash: hash, p_status: status, p_error: error });
      if (seen.error) throw new Error('source_seen: ' + seen.error.message);
      if (seen.data?.changed) changed++;
    }
    const settled = await admin.rpc('fn_marketing_platform_spec_freshness');
    if (settled.error) throw new Error('freshness: ' + settled.error.message);
    return { due: urls.length > 0, read: urls.length, changed, open_findings: settled.data?.failing ?? null };
  },
};
