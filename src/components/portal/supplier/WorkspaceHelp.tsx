// HELP IS ALWAYS ONE TAP AWAY (12 Nov 2026, sales_engineer, built by it_engineer; walk of 12 Nov 2026, S13; founder ruling 1645).
// The approved workspace had no help, support, contact or Supplier Agreement link: the visible links were the logo and, on Settings,
// the Privacy Policy; the agreement was reachable only through the terms box on Profile; the support address was shown only on the
// not-approved card (core/Dashboard.tsx RegistrationNotApproved); and "Home" is hidden under 640 px (SupplierPortal.tsx header).
// This line closes the workspace on every tab and every size. Only what the company publishes: the address the portal and the
// Contact page already give (registrationReceived.ts SUPPORT_EMAIL, ContactInner.tsx), the Contact page, the Supplier Agreement, the
// Privacy Policy and Home. No WhatsApp number is published, so none is shown. English only (ruling 1008).
// Guard: src/components/portal/supplier/workspaceHelp.test.mjs
import { SUPPORT_EMAIL } from './registrationReceived';

const link = 'inline-flex min-h-11 items-center font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-ring rounded-sm';

export default function WorkspaceHelp() {
  return (
    <nav aria-label="Help" data-testid="workspace-help" dir="ltr" lang="en"
      className="mx-auto mb-8 flex max-w-[1040px] flex-wrap items-center gap-x-5 gap-y-0 border-t border-border px-[22px] pt-3 text-[14px] text-muted-foreground">
      <span>Questions? Write to <a className={link} href={'mailto:' + SUPPORT_EMAIL}>{SUPPORT_EMAIL}</a></span>
      <a className={link} href="/contact" target="_blank" rel="noopener">Contact us</a>
      <a className={link} href="/supplier-agreement" target="_blank" rel="noopener">Supplier Agreement</a>
      <a className={link} href="/privacy" target="_blank" rel="noopener">Privacy Policy</a>
      <a className={link} href="/">QuotesDone home</a>
    </nav>
  );
}
