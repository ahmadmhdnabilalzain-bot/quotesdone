// WHAT HE HAS TYPED SURVIVES A RELOAD, A BACK OR A TAB SWITCH (12 Nov 2026, customer_support; browser perfection walk H7 and M3,
// founder ruling 1645).
//
// Measured on production at 390x844 (scen_resume reload_mid_form): after a reload the emirates went 1 -> 0, the mobile, the
// contact name, the chosen company profile and the agreement tick were gone; only the licence, already on the server, stayed.
// At the code step a reload or Back dropped the step and the address, and he retyped it under "Welcome back". The form leaves
// the page three times (the e-mail code, the mobile code, the agreement), and an iPhone drops a tab it has put away.
//
// What is kept: in sessionStorage (this tab only, gone when the tab closes), the fields he typed or ticked and the NAMES of the
// files he chose, so the form can say which to choose again. Never a file's bytes (a browser cannot keep a picked file), never a
// code, never a token. The draft names the account it belongs to and is read back only for that account. It is cleared when he
// submits, and by clearRegistrationDrafts at sign-out. Every storage call is wrapped: a private window may refuse it.
// Prevented by: src/components/portal/supplier/registrationDraft.test.mjs.

type Store = { getItem(k: string): string | null; setItem(k: string, v: string): void; removeItem(k: string): void; key?(i: number): string | null; length?: number };
export const DRAFT_PREFIX = 'qd-reg-draft:';
export const LOGIN_DRAFT = 'qd-login-draft';
/** A sign-in code lives 10 minutes (login_otp fn_login_otp_email_issue p_ttl_seconds 600); the code step is kept as long. */
export const CODE_LIFE_MS = 10 * 60_000;
const DAY_MS = 24 * 3600_000;

export type RegDraft = {
  owner: string; at: number;
  emirates: string[]; phone: string; contact_name: string; terms: boolean; marketing: boolean;
  profile_name: string | null; catalogue_names: string[];
};
const str = (v: unknown, max = 200) => (typeof v === 'string' ? v.slice(0, max) : '');

export const draftKey = (me: { id?: unknown; claimed_by?: unknown }) => DRAFT_PREFIX + String(me?.id ?? me?.claimed_by ?? 'me');

/** Only the fields that may be kept, whatever the form's state holds besides. */
export function draftOf(owner: string, s: { emirates?: unknown; phone?: unknown; contact_name?: unknown; terms?: unknown; marketing?: unknown;
  profileFile?: { name?: string } | null; catalogFiles?: { name?: string }[] }, now = Date.now()): RegDraft {
  return {
    owner: str(owner), at: now,
    emirates: Array.isArray(s.emirates) ? s.emirates.filter((e) => typeof e === 'string').slice(0, 7) : [],
    phone: str(s.phone, 40), contact_name: str(s.contact_name, 120), terms: s.terms === true, marketing: s.marketing === true,
    profile_name: s.profileFile?.name ? str(s.profileFile.name) : null,
    catalogue_names: (s.catalogFiles || []).map((f) => str(f?.name)).filter(Boolean).slice(0, 5),
  };
}
export function saveDraft(store: Store | null | undefined, key: string, d: RegDraft): void {
  try { store?.setItem(key, JSON.stringify(d)); } catch (_e) { /* a private window: nothing is kept, nothing breaks */ }
}
/** The draft for this account, when there is one from the last day; anything else is null. */
export function readDraft(store: Store | null | undefined, key: string, owner: string, now = Date.now()): RegDraft | null {
  let d: Partial<RegDraft> | null = null;
  try { d = JSON.parse(store?.getItem(key) || 'null'); } catch (_e) { d = null; }
  if (!d || typeof d !== 'object' || d.owner !== str(owner) || !(now - Number(d.at) < DAY_MS)) return null;
  return draftOf(str(owner), { ...d, profileFile: d.profile_name ? { name: d.profile_name } : null, catalogFiles: (d.catalogue_names || []).map((name) => ({ name })) }, Number(d.at));
}
/** Every registration draft and the code step, gone (submit, sign-out). */
export function clearRegistrationDrafts(store: Store | null | undefined): void {
  try {
    if (!store) return;
    const keys: string[] = [];
    for (let i = 0; i < Number(store.length || 0); i++) { const k = store.key?.(i); if (k && (k.startsWith(DRAFT_PREFIX) || k === LOGIN_DRAFT)) keys.push(k); }
    for (const k of keys) store.removeItem(k);
  } catch (_e) { /* nothing kept to clear */ }
}
/** What the form says after a reload when he had chosen files: which to choose again. Empty when nothing is to be chosen. */
export function chooseAgainNote(d: RegDraft | null, still: { profile: boolean; catalogues: boolean }): string {
  if (!d) return '';
  const names = [...(still.profile && d.profile_name ? [d.profile_name] : []), ...(still.catalogues ? d.catalogue_names : [])];
  if (!names.length) return '';
  return `The page reloaded, so please choose ${names.length === 1 ? 'this file' : 'these files'} again: ${names.join(', ')}. Everything you typed and ticked is still here.`;
}

// ── the code step (src/components/portal/supplier/core/Login.tsx) ─────────────────────────────────────────────────────
export type LoginDraft = { mode: 'signin' | 'signup'; step: 'id' | 'code'; ident: string; at: number };
export function saveLoginDraft(store: Store | null | undefined, d: Omit<LoginDraft, 'at'>, now = Date.now()): void {
  try { store?.setItem(LOGIN_DRAFT, JSON.stringify({ mode: d.mode === 'signup' ? 'signup' : 'signin', step: d.step === 'code' ? 'code' : 'id', ident: str(d.ident), at: now })); } catch (_e) { /* not kept */ }
}
/** The code step comes back while its code can still be used; later, the address comes back on the first step. */
export function readLoginDraft(store: Store | null | undefined, now = Date.now()): LoginDraft | null {
  let d: Partial<LoginDraft> | null = null;
  try { d = JSON.parse(store?.getItem(LOGIN_DRAFT) || 'null'); } catch (_e) { d = null; }
  if (!d || typeof d !== 'object' || !str(d.ident) || !(now - Number(d.at) < DAY_MS)) return null;
  const fresh = now - Number(d.at) < CODE_LIFE_MS;
  return { mode: d.mode === 'signup' ? 'signup' : 'signin', step: d.step === 'code' && fresh ? 'code' : 'id', ident: str(d.ident), at: Number(d.at) };
}
export function clearLoginDraft(store: Store | null | undefined): void { try { store?.removeItem(LOGIN_DRAFT); } catch (_e) { /* nothing */ } }
