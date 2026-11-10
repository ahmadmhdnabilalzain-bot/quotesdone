
// THE DASHBOARD IS A JOURNEY, NOT 24 TABS (14 Sep 2026).
//
// It had 24 equal tabs; on a 375x812 phone the strip alone was 366px tall and the one action that
// unlocks every RFQ sat 2,547px down (measurements recorded in CapabilityConfirmPanel). Now: the
// overview is "Get matched" (the eligibility payload as a progress ring and checklist), then the core
// work — RFQs, Quotes, Projects, Messages, Documents, Billing — and ONE Insights section that lists only
// the intelligence panels whose routine has something to show. Profile, scope and settings are account
// links; the checklist sends the supplier to whichever one is next. The strip scrolls sideways rather
// than wrapping, so on a phone it is one row.
//
// 15 SEP 2026, THE FOUNDER'S ORDER: Services, Inquiries received, Quotations submitted, Messages,
// Documents, Insights; Profile, Billing and Settings in an account menu. The "Get matched" overview was
// dropped ("drop it"): its alerts are the bell, its registration checklist heads the Documents tab, and its
// tiles, funnel and price position are the Insights tab. Projects (revealed jobs) fold into Messages.
// Services is ./supplier/ServicesTab (#722: the services checklist inside the confirmed trades) and is the landing tab.
// Old keys still resolve through go(): overview/scope -> services, projects -> messages, inbox -> rfqs.
const MAIN_TABS = ['services', 'rfqs', 'quotes', 'messages', 'documents', 'insights'];
const ACCOUNT_TABS = ['profile', 'billing', 'settings'];
const TAB_ALIAS = { overview: 'services', scope: 'services', projects: 'messages', inbox: 'rfqs' };
export { MAIN_TABS, ACCOUNT_TABS, TAB_ALIAS };
