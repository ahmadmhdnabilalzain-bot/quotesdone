// WHAT A PHONE TAP DOES TO THE PORTAL'S OPEN PANELS (ceo, journey verification 10 Nov 2026).
//
// Measured on production 10 Nov 2026 (e2e run tag b9d7d1d5, journey f, 375 px): once the account assistant was open,
// tapping "My requests" or "Documents" in the tab bar changed the active tab UNDER the assistant, which is full width
// below 640 px, so the screen did not change; and tapping "More" opened its sheet UNDER the assistant (both z-40, the
// assistant later in the DOM), so the More button turned into an X and nothing appeared. The crawl could not reach
// 7 of 10 destinations in English and Arabic. Escape closed the More sheet and the bell but not the assistant, though
// PortalShell's focus-return comment says Escape closes all three.
//
// The rule, in one place so it can be tested without a browser:
//   - choosing a destination closes the More sheet, and closes the assistant where the assistant covers the page;
//   - opening the More sheet closes the assistant (the sheet exists only below md, where the assistant would hide it);
//   - Escape closes every panel.
// prevented by: scripts/checks/a_phone_tap_is_never_hidden_under_the_assistant.test.mjs
export interface Panels { asst: boolean; more: boolean; bell: boolean }

/** A destination was chosen. `assistantCoversPage` is true below 640 px, where the assistant is full width. */
export function afterNavigate(p: Panels, assistantCoversPage: boolean): Panels {
  return { ...p, more: false, asst: assistantCoversPage ? false : p.asst };
}

/** The More button was pressed: it opens or closes the sheet, and an opening sheet is never hidden by the assistant. */
export function afterMoreToggle(p: Panels): Panels {
  const more = !p.more;
  return { ...p, more, asst: more ? false : p.asst };
}

/** Escape closes every panel. */
export function afterEscape(p: Panels): Panels {
  return { ...p, asst: false, more: false, bell: false };
}
