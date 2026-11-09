// @ts-nocheck
import { supaClient } from '@/lib/supaClient';
import { call } from '../api';
// THE DASHBOARD'S FIRST READ STARTS WITH THE TOKEN (15 Sep 2026), the way the customer portal's does
// (me/prefetch.ts): the moment a token is known the combined `dashboard` call is started, and Dashboard's
// first load takes that promise instead of asking again. Every later load asks the server fresh.
import { warm } from '@/components/me/prefetch';

const DASH_KEY = 'sup_dash';
const fetchDashboard = (tk) => call('supplier_portal', { action: 'dashboard' }, tk);
const warmSupplier = (tk) => warm(tk, DASH_KEY, () => fetchDashboard(tk));
const SB = () => supaClient('qd-portal-auth');
export { DASH_KEY, fetchDashboard, warmSupplier, SB };
