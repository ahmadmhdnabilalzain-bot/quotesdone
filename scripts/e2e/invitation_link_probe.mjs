// THE LINK THE FOUNDER TEXTS, READ THE WAY A PHONE AND WHATSAPP READ IT (15 Nov 2026, customer_support; founder ledger 1692:
// "perfection" for the invitations he sends his own network on Monday 16 Nov).
//
// The registration certification (supplier_registration_certification.mjs) starts INSIDE the page. Nothing proved the link
// itself: what WhatsApp's preview card shows (it reads the Open Graph tags of the raw HTML, no script runs), that every way a
// person may type or forward the link lands on the same page (http, www, .ae, a trailing slash), that the card's picture is
// small enough to be shown, and that the two buttons of the public supplier page lead to the sign-up door. This does that with
// plain GETs: no sign-up, no script, no write, no model call, USD 0. Safe to run against production at any time.
//
//   node scripts/e2e/invitation_link_probe.mjs              # quotesdone.com and quotesdone.ae, prints PASS/FAIL per check
//   node scripts/e2e/invitation_link_probe.mjs --json out.json
//
// What it cannot see, said plainly: what a UAE visitor gets on quotesdone.com (Vercel sends a UAE address to quotesdone.ae with a
// 308; this container is in the US, so only the .ae target itself is read), what WhatsApp's own crawler caches (a card is cached
// by WhatsApp per URL for days), and anything the page does once its script runs (the certification and the founder's phone).
// The pure judges below are tested offline by invitation_link_probe.test.mjs.

export const JOIN_PATH = '/portal?join=1';
export const HOSTS = ['https://quotesdone.com', 'https://quotesdone.ae'];
// A picture larger than this is often dropped from a WhatsApp preview. WhatsApp publishes no limit; 300 KB is the figure
// commonly cited by people who measured it, so it is the bar here, not a documented rule.
export const OG_IMAGE_MAX_BYTES = 300 * 1024;
const WHATSAPP_UA = 'WhatsApp/2.24.1.0 A';

/** The <meta>/<title> facts a link preview reads, from raw HTML. Attribute order may vary; only the first of each is kept. */
export function headFacts(html) {
  const s = String(html || '');
  const metas = {};
  for (const m of s.matchAll(/<meta\s+[^>]*>/gi)) {
    const tag = m[0];
    const key = (/\b(?:property|name)="([^"]+)"/i.exec(tag) || [])[1];
    const content = (/\bcontent="([^"]*)"/i.exec(tag) || [])[1];
    if (key && content !== undefined && !(key in metas)) metas[key] = content.replace(/&amp;/g, '&');
  }
  const title = ((/<title>([^<]*)<\/title>/i.exec(s) || [])[1] || '').replace(/&amp;/g, '&');
  const htmlTag = (/<html\b[^>]*>/i.exec(s) || [''])[0];
  const lang = (/\blang="([^"]+)"/i.exec(htmlTag) || [])[1] || '';
  const dir = (/\bdir="([^"]+)"/i.exec(htmlTag) || [])[1] || '';
  const canonical = (/<link\s+rel="canonical"\s+href="([^"]+)"/i.exec(s) || [])[1] || '';
  return { title, lang, dir, canonical, metas };
}

/** Problems with a page's preview card; [] when WhatsApp, iMessage and LinkedIn all have what they need. */
export function judgeCard(facts, { lang = 'en' } = {}) {
  const bad = [];
  const m = facts.metas || {};
  for (const k of ['og:title', 'og:description', 'og:image', 'og:url', 'twitter:card']) if (!m[k]) bad.push(`no ${k}`);
  if (m['og:image'] && !/^https:\/\//.test(m['og:image'])) bad.push(`og:image is not an absolute https URL: ${m['og:image']}`);
  if (m['og:title'] && /undefined|null|\{|\}/.test(m['og:title'])) bad.push(`og:title carries a template artefact: ${m['og:title']}`);
  if (m['og:description'] && m['og:description'].length < 30) bad.push('og:description is too short to say what the page is');
  if (!facts.title) bad.push('no <title>');
  if (facts.lang !== lang) bad.push(`html lang is "${facts.lang}", expected "${lang}"`);
  if (lang === 'ar' && facts.dir !== 'rtl') bad.push('an Arabic page is not dir="rtl"');
  return bad;
}

/** Problems with a redirect; [] when `status`/`location` send the person to exactly `want` in one permanent hop. A relative
 *  Location is read against the URL that was asked (`from`), as a browser reads it. */
export function judgeRedirect({ status, location }, want, from = want) {
  if (![301, 308].includes(Number(status))) return [`answered ${status}, expected one permanent redirect (301/308) to ${want}`];
  let to = String(location || '');
  try { to = new URL(to, from).href; } catch (_e) { /* kept as sent */ }
  if (to !== want) return [`redirects to ${location || '(nothing)'}, expected ${want}`];
  return [];
}

/** Problems with the preview picture; [] when it is a PNG/JPEG of the 1.91:1 card shape and small enough to be shown. */
export function judgeOgImage({ status, contentType, bytes, width, height }) {
  const bad = [];
  if (Number(status) !== 200) bad.push(`answered ${status}`);
  if (!/^image\/(png|jpeg)$/.test(String(contentType || ''))) bad.push(`content-type ${contentType}`);
  if (!(Number(bytes) > 0)) bad.push('empty');
  if (Number(bytes) > OG_IMAGE_MAX_BYTES) bad.push(`${bytes} bytes, over ${OG_IMAGE_MAX_BYTES}`);
  if (width && height && Math.abs(width / height - 1.91) > 0.05) bad.push(`${width}x${height} is not the 1.91:1 card shape`);
  return bad;
}

/** The size of a PNG from its IHDR, or of a JPEG from its first SOFn; null when neither. */
export function imageSize(buf) {
  const b = Buffer.from(buf);
  if (b.length > 24 && b.readUInt32BE(0) === 0x89504e47) return { width: b.readUInt32BE(16), height: b.readUInt32BE(20) };
  if (b.length > 4 && b[0] === 0xff && b[1] === 0xd8) {
    let i = 2;
    while (i + 9 < b.length) {
      if (b[i] !== 0xff) { i++; continue; }
      const marker = b[i + 1]; const len = b.readUInt16BE(i + 2);
      if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) return { width: b.readUInt16BE(i + 7), height: b.readUInt16BE(i + 5) };
      i += 2 + len;
    }
  }
  return null;
}

/** Every link a person may be given or may type, with what it must do. Pure, so the test can hold the list. */
export function entryChecks(hosts = HOSTS) {
  const out = [];
  for (const h of hosts) {
    const apex = new URL(h).host; const www = 'www.' + apex;
    out.push({ id: `card:${apex}`, url: h + JOIN_PATH, kind: 'card', lang: 'en' });
    out.push({ id: `http:${apex}`, url: `http://${apex}${JOIN_PATH}`, kind: 'redirect', want: h + JOIN_PATH });
    out.push({ id: `www:${apex}`, url: `https://${www}${JOIN_PATH}`, kind: 'redirect', want: h + JOIN_PATH });
    out.push({ id: `slash:${apex}`, url: `${h}/portal/?join=1`, kind: 'redirect', want: h + JOIN_PATH });
    out.push({ id: `supplier:${apex}`, url: h + '/supplier', kind: 'card', lang: 'en', ctaTo: JOIN_PATH });
  }
  out.push({ id: 'supplier_ar', url: hosts[0] + '/ar/supplier', kind: 'card', lang: 'ar', ctaTo: '/ar' + JOIN_PATH });
  // The Arabic CTA lands on /ar/portal; the portal itself is English for every supplier (ruling 1008) and moves there on load.
  out.push({ id: 'portal_ar', url: hosts[0] + '/ar' + JOIN_PATH, kind: 'card', lang: 'ar' });
  return out;
}

async function get(url, ua) {
  const r = await fetch(url, { redirect: 'manual', headers: { 'user-agent': ua || WHATSAPP_UA }, signal: AbortSignal.timeout(20000) });
  const buf = Buffer.from(await r.arrayBuffer());
  return { status: r.status, location: r.headers.get('location'), contentType: (r.headers.get('content-type') || '').split(';')[0], buf };
}

export async function runProbe(hosts = HOSTS) {
  const results = []; const images = new Set();
  for (const c of entryChecks(hosts)) {
    const t0 = Date.now(); let bad = []; let facts = null;
    try {
      const r = await get(c.url);
      if (c.kind === 'redirect') bad = judgeRedirect(r, c.want, c.url);
      else {
        if (r.status !== 200) bad.push(`answered ${r.status}`);
        facts = headFacts(r.buf.toString('utf8'));
        bad.push(...judgeCard(facts, { lang: c.lang }));
        if (c.ctaTo && !r.buf.toString('utf8').includes(`href="${c.ctaTo}"`)) bad.push(`no button leads to ${c.ctaTo}`);
        if (facts.metas['og:image']) images.add(facts.metas['og:image']);
      }
    } catch (e) { bad.push('request failed: ' + String(e?.message || e)); }
    results.push({ id: c.id, url: c.url, ok: !bad.length, bad, ms: Date.now() - t0, title: facts?.metas?.['og:title'] });
  }
  for (const url of images) {
    let bad = []; let meta = {};
    try { const r = await get(url); const size = imageSize(r.buf) || {}; meta = { bytes: r.buf.length, ...size }; bad = judgeOgImage({ status: r.status, contentType: r.contentType, bytes: r.buf.length, ...size }); }
    catch (e) { bad = ['request failed: ' + String(e?.message || e)]; }
    results.push({ id: 'og_image', url, ok: !bad.length, bad, ...meta });
  }
  return results;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const results = await runProbe();
  for (const r of results) console.log(`${r.ok ? 'PASS' : 'FAIL'} ${r.id} ${r.url}${r.ok ? '' : ' - ' + r.bad.join('; ')}`);
  const i = process.argv.indexOf('--json');
  if (i > 0 && process.argv[i + 1]) (await import('node:fs')).writeFileSync(process.argv[i + 1], JSON.stringify({ at: new Date().toISOString(), results }, null, 1));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`${results.length - failed} of ${results.length} pass`);
  process.exit(failed ? 1 : 0);
}
