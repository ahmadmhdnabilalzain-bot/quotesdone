// A WINDOW OPENED AFTER AN AWAIT IS A POPUP. These buttons used to `await` the signed URL and only
// then call window.open — by which time the click's user activation can have lapsed, and Safari and
// strict popup settings drop the window silently: the customer presses the quotation and nothing
// opens. The tab is now opened INSIDE the click, shows a one-line holding message, and is pointed
// at the document when the URL arrives (or closed again if it does not). 14 Sep 2026, agent: ceo.
// Moved here from CustomerPortal.tsx on 15 Sep 2026 so the supplier portal's PDFs use the same door.
export async function openDocument(lang: string, fetchUrl: () => Promise<string | null>): Promise<boolean> {
  let w: Window | null = null;
  try { w = window.open('', '_blank'); } catch (_e) { w = null; }
  if (w) { try { w.document.title = 'QuotesDone'; w.document.body.style.cssText = 'font:14px system-ui,sans-serif;padding:24px;color:#0c2330'; w.document.body.textContent = lang === 'ar' ? 'جارٍ تجهيز المستند…' : 'Preparing your document…'; } catch (_e) { /* cross-origin already */ } }
  let url: string | null = null;
  try { url = await fetchUrl(); } catch (_e) { url = null; }
  if (url) {
    if (w && !w.closed) { try { w.opener = null; } catch (_e) { /* */ } w.location.replace(url); } else window.open(url, '_blank', 'noopener');
    return true;
  }
  if (w && !w.closed) w.close();
  return false;
}
