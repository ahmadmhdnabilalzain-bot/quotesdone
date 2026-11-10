// The chat bubble's HTML: escape the text, then turn URLs, e-mail addresses, our own paths and phone numbers into
// links or isolated runs. Each one is wrapped in <bdi> so it stays readable inside Arabic (right-to-left) text.
// Used by the site widget (ChatWidget.tsx) and the portal assistant (me/shell/AssistantPanel.tsx), both through
// dangerouslySetInnerHTML, so this is the one place a reply's text becomes markup. Half the UAE market reads the
// Arabic; an e-mail address or a +971 number rendered without isolation scrambles inside an RTL paragraph, and a rule
// that exists twice is a rule that will be applied once.
//
// ONE PASS, NOT FOUR (it_engineer, security checklist audit 10 Nov 2026, XSS row). This used to run four replace()
// calls in a row over the growing HTML, so each later pattern also matched inside the markup an earlier one had
// written: an e-mail inside a URL put a second <a href="mailto:…"> INSIDE the first link's href attribute and closed
// it early, and a run of 8+ digits in a URL put <bdi> inside the href (measured: "https://a.co/1234567890" rendered an
// href of "https://a.co/<bdi>1234567890</bdi>"). No script ran, because every character the patterns can carry is
// escaped first, but an attribute closed by generated markup is one pattern change away from an injection. Now each
// span of the escaped text is matched once, by the first pattern that fits at that position, and the output of one
// is never read by another. Prevented by scripts/checks/the_chat_renderer_never_writes_a_link_inside_a_link.test.mjs.
const LINK = 'style="color:#2DD4BF;font-weight:600"';
const TOKEN = /(https?:\/\/[^\s<]+)|([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})|(^|[\s(])(\/(?:ar\/me|contact|me|portal|supplier|faq|services|blog|about)\/?)(?![\w-])|(\+?\d[\d\s\-()]{6,}\d)/g;

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

export function render(text: string): string {
  const h = escapeHtml(String(text ?? '')).replace(TOKEN, (_m, url, mail, lead, path, phone) => {
    if (url) return `<bdi><a href="${url}" target="_blank" rel="noopener noreferrer" ${LINK}>${url}</a></bdi>`;
    if (mail) return `<bdi><a href="mailto:${mail}" ${LINK}>${mail}</a></bdi>`;
    if (path) return `${lead}<bdi><a href="${path}" ${LINK}>${path}</a></bdi>`;
    return `<bdi>${phone}</bdi>`;
  });
  return h.replace(/\n/g, '<br>');
}
