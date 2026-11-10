// The tag scan the content renderers (DocFrame, LegalDoc, MarketingDoc) read our own content files with.
// No imports, so scripts/checks can load it directly. Parsing is of our committed JSON, never user input.

/** End index (exclusive) of the element that opens at `start`, balancing tags of the same name. */
function elementEnd(html: string, start: number): number {
  const name = /^<([a-z0-9]+)/i.exec(html.slice(start))?.[1];
  if (!name) return -1;
  const re = new RegExp(`<(/?)${name}\\b[^>]*>`, 'gi');
  re.lastIndex = start;
  let depth = 0;
  for (let m = re.exec(html); m; m = re.exec(html)) {
    depth += m[1] ? -1 : 1;
    if (depth === 0) return m.index + m[0].length;
  }
  return -1;
}

/** The first element carrying `cls` in its class list: its outer html and the html around it. */
export function takeByClass(html: string, cls: string): { el: string; before: string; after: string } | null {
  const m = new RegExp(`<[a-z0-9]+\\b[^>]*class="(?:[^"]*\\s)?${cls}(?:\\s[^"]*)?"[^>]*>`, 'i').exec(html);
  if (!m) return null;
  const end = elementEnd(html, m.index);
  if (end < 0) return null;
  return { el: html.slice(m.index, end), before: html.slice(0, m.index), after: html.slice(end) };
}

// THE SUPPLIER AGREEMENT'S BODY IS CLOSED HERE, NOT IN THE FILE (website audit 10 Nov 2026, customer_support).
// Every Supplier Agreement in legal.json (v10 to v17, both languages) opens one more <div> than it closes:
// the </div> of .body is missing before .note. takeByClass(html, 'body') then finds no end, and LegalDoc
// fell back to the WHOLE file. Measured on production: /supplier-agreement printed the document switcher
// and a second visible <h1> under the hero, and its meta description was the switcher's link labels. The
// text cannot be edited: its sha256 is what live suppliers accepted (leads.accepted_terms_sha256, pinned by
// the_founders_mobile_is_in_no_current_public_text_and_a_contact_only_version_asks_nobody_to_sign_again).
// So the one missing close is restored at render, only when .body has no end of its own and only in front
// of .note; a balanced document comes back unchanged.
export function closeUnclosedBody(html: string): string {
  if (takeByClass(html, 'body') || !takeByClass(html, 'note')) return html;
  return html.replace(/<div class="note">/, '</div><div class="note">');
}

// Each legal file's .body opens with its own <h1>, the same words as the hero's; globals.css already hid it
// (.legalx .body > h1:first-of-type). It is dropped from the markup so the page has ONE <h1> (measured
// 10 Nov 2026: every legal page carried two in its HTML, the Supplier Agreement three).
export function dropFirstH1(html: string): string {
  return html.replace(/<h1\b[^>]*>[\s\S]*?<\/h1>/i, '');
}
