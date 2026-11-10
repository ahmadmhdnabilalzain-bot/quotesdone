// @ts-nocheck
'use client';
// THE CUSTOMER PORTAL (/me). Split by subject on 9 Nov 2026 from one 2,156-line file, as a pure move:
// every statement kept as it was, only the imports between the new files added. Where things live:
//   api.ts     the edge-function transport (call, tokenAlive, warmDashboard) and the auth client SB
//   format.ts  money, greeting, RFQ stage, supplier label and rating helpers;  styles.ts  the class map S
//   auth/      the signed-out and signed-in frame: CustomerPortalView, AuthShell, Login, ProfileGate, Authed
//   dashboard/ the overview (Dashboard), the module windows, account settings, the lazily loaded modules
//   requests/  one request's card, its quotes, comparison, documents, progress and facts
// The checks that read the portal as text read all of these, through scripts/lib/portal_sources.mjs.
// Website audit 14 Sep 2026: the intake composer, the pre-reveal Q&A, the Reveal Guarantee and the
// in-page confirm each live in their own file under src/components/me; this file wires them in.
import { MotionRoot } from './lazyMotion';
import { CustomerPortalView } from './auth/CustomerPortalView';

export function CustomerPortal() { return <MotionRoot><CustomerPortalView /></MotionRoot>; }
