// portal_sources.mjs — which source files make up each portal, for the checks that read them as TEXT.
//
// Until 9 Nov 2026 each portal was one file (src/components/me/CustomerPortal.tsx, 2,156 lines, and
// src/components/portal/SupplierPortal.tsx, 2,084 lines), and some fifty checks read that one file and
// asserted a property of its text. Both were split by subject that day, as a pure move: every
// statement kept byte for byte, only the imports between the new files added. A check that kept
// reading the entry file alone would now be reading a short wrapper and pass or fail on nothing, so
// the checks read the portal through here instead: the same text, in the order it stood in the
// original file (by the first line each new file took from it), joined by a newline.
//
// The list is closed, not globbed, so the order is fixed; portal_sources.test.mjs fails when a file
// is added to one of the split folders and not named here, so a new file cannot fall outside the
// checks unseen.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

export const REPO = join(import.meta.dirname, '..', '..');

/** The customer portal (/me), entry src/components/me/CustomerPortal.tsx. */
export const CUSTOMER_PORTAL_FILES = [
  'src/components/me/dashboard/lazyModules.tsx',
  'src/components/me/api.ts',
  'src/components/me/auth/CustomerPortalView.tsx',
  'src/components/me/format.ts',
  'src/components/me/styles.ts',
  'src/components/me/auth/AuthShell.tsx',
  'src/components/me/auth/Login.tsx',
  'src/components/me/auth/Authed.tsx',
  'src/components/me/auth/ProfileGate.tsx',
  'src/components/me/auth/acceptTerms.ts',
  'src/components/me/dashboard/Dashboard.tsx',
  'src/components/me/requests/InquiryCard.tsx',
  'src/components/me/requests/Comparison.tsx',
  'src/components/me/requests/Contact.tsx',
  'src/components/me/requests/QuoteDocs.tsx',
  'src/components/me/requests/QuoteCard.tsx',
  'src/components/me/requests/Progress.tsx',
  'src/components/me/requests/DetailFacts.tsx',
  'src/components/me/dashboard/ModuleWindow.tsx',
  'src/components/me/dashboard/AccountSettings.tsx',
  'src/components/me/CustomerPortal.tsx',
];

/** The folders the customer portal was split into; every .ts/.tsx in them must be listed above. */
export const CUSTOMER_PORTAL_DIRS = ['src/components/me/auth', 'src/components/me/dashboard', 'src/components/me/requests'];

/** The supplier portal (/portal), entry src/components/portal/SupplierPortal.tsx. */
export const SUPPLIER_PORTAL_FILES = [
  'src/components/portal/supplier/core/session.ts',
  'src/components/portal/supplier/core/helpers.tsx',
  // upload.ts follows Billing, not precedes it: its last statement, fileToImages, stood directly above the T
  // dictionary (copy.ts) in the old file, and a check that strips "<...>" spans (company_facts_agree_everywhere,
  // via plain()) reads the `i < raw.length` in it as the start of one. Kept in that order so every check sees
  // exactly the text it saw before the split.
  'src/components/portal/supplier/core/Billing.tsx',
  'src/components/portal/supplier/core/upload.ts',
  'src/components/portal/supplier/core/copy.ts',
  'src/components/portal/supplier/core/styles.ts',
  'src/components/portal/supplier/core/ClaimRefusal.tsx',
  'src/components/portal/SupplierPortal.tsx',
  'src/components/portal/supplier/core/Login.tsx',
  'src/components/portal/supplier/core/tabs.ts',
  'src/components/portal/supplier/core/Agreement.tsx',
  'src/components/portal/supplier/core/HeaderMenus.tsx',
  'src/components/portal/supplier/core/Dashboard.tsx',
  'src/components/portal/supplier/core/QuoteForm.tsx',
  'src/components/portal/supplier/core/Documents.tsx',
  'src/components/portal/supplier/core/Projects.tsx',
  'src/components/portal/supplier/core/Onboarding.tsx',
  'src/components/portal/supplier/core/ProfileForm.tsx',
];

/** The folder the supplier portal was split into (the rest of portal/supplier/ predates the split). */
export const SUPPLIER_PORTAL_DIRS = ['src/components/portal/supplier/core'];

/** The request composer (src/components/me/NewRequest.tsx), split into src/components/me/newRequest/ the same way (9 Nov 2026). */
export const NEW_REQUEST_FILES = [
  'src/components/me/newRequest/helpers.ts',
  'src/components/me/NewRequest.tsx',
  'src/components/me/newRequest/RequirementsCard.tsx',
  'src/components/me/newRequest/Readiness.tsx',
  'src/components/me/newRequest/BoqTable.tsx',
  'src/components/me/newRequest/RedactionEditor.tsx',
];
export const NEW_REQUEST_DIRS = ['src/components/me/newRequest'];

/** The portal shell (src/components/me/PortalShell.tsx), split into src/components/me/shell/ the same way. */
export const PORTAL_SHELL_FILES = [
  'src/components/me/shell/navGroups.ts',
  'src/components/me/shell/AssistantPanel.tsx',
  'src/components/me/shell/StatusParts.tsx',
  'src/components/me/PortalShell.tsx',
];
export const PORTAL_SHELL_DIRS = ['src/components/me/shell'];

const readAll = (files) => files.map((f) => {
  const p = join(REPO, f);
  if (!existsSync(p)) throw new Error(`scripts/lib/portal_sources.mjs names ${f}, which does not exist: update the list`);
  return readFileSync(p, 'utf8');
}).join('\n');

/** The customer portal's whole source text, in its original order. */
export const readCustomerPortal = () => readAll(CUSTOMER_PORTAL_FILES);

/** The supplier portal's whole source text, in its original order. */
export const readSupplierPortal = () => readAll(SUPPLIER_PORTAL_FILES);

/** The request composer's whole source text, in its original order. */
export const readNewRequest = () => readAll(NEW_REQUEST_FILES);

/** The portal shell's whole source text, in its original order. */
export const readPortalShell = () => readAll(PORTAL_SHELL_FILES);

const ENTRIES = {
  'src/components/me/CustomerPortal.tsx': readCustomerPortal,
  'src/components/portal/SupplierPortal.tsx': readSupplierPortal,
  'src/components/me/NewRequest.tsx': readNewRequest,
  'src/components/me/PortalShell.tsx': readPortalShell,
};

/** Read a source file by its repo path; a portal's ENTRY path reads that whole portal instead. */
export const readSource = (p) => (ENTRIES[p] ? ENTRIES[p]() : readFileSync(join(REPO, p), 'utf8'));
