import { supaClient } from '@/lib/supaClient';
import { call } from '../api';
// THE DASHBOARD'S FIRST READ STARTS WITH THE TOKEN (15 Sep 2026), the way the customer portal's does
// (me/prefetch.ts): the moment a token is known the combined `dashboard` call is started, and Dashboard's
// first load takes that promise instead of asking again. Every later load asks the server fresh.
import { warm } from '@/components/me/prefetch';

const DASH_KEY = 'sup_dash';
const fetchDashboard = (tk: string) => call('supplier_portal', { action: 'dashboard' }, tk);
// AND `me` STARTS WITH IT (11 Nov 2026, customer_support; registration certification finding 9). Whether the account has a company,
// and whether it has submitted its registration, is `me`'s answer as much as the dashboard's; Dashboard opens the registration on
// whichever lands first. Started here, beside the dashboard, it no longer waits for the portal to mount.
const ME_KEY = 'sup_me';
const fetchMe = (tk: string) => call('supplier_api', { action: 'me' }, tk);
// `withMe` false (sign-in said there is no company yet: src/lib/supplierRegistrationReads.ts warmsMe) warms the dashboard only.
const warmSupplier = (tk: string, withMe = true) => { warm(tk, DASH_KEY, () => fetchDashboard(tk)); if (withMe) warm(tk, ME_KEY, () => fetchMe(tk)); };
const SB = () => supaClient('qd-portal-auth');
export { DASH_KEY, ME_KEY, fetchDashboard, fetchMe, warmSupplier, SB };
