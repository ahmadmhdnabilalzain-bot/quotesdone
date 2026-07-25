'use client';
import { createClient } from '@supabase/supabase-js';
export const SUPA_URL = 'https://htdblwldjkcgjvmqkbeh.supabase.co';
export const SUPA_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0ZGJsd2xkamtjZ2p2bXFrYmVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3ODU1NDYsImV4cCI6MjA5NjM2MTU0Nn0.cF9ZR_Qo1YBhLvhTLS8aANlYb6c9rTsuQS6kLxGw_Bo';
export const supa = createClient(SUPA_URL, SUPA_ANON, { auth: { persistSession: true, autoRefreshToken: true } });
export async function osApi(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_api', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) {
    throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error'));
  } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j.data;
}
export async function osReportBody(id: number) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/report_body', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ id }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j as { ok: boolean; found: boolean; report?: any; note?: string };
}
export async function osOps(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_ops', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j.data;
}
export async function osSettings(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_settings', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j.data;
}
export async function osAutomation(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_automation', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j.data;
}
export async function osCatalog(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_catalog', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j.data;
}
export async function osPages(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 40000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_pages', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j.data;
}
export async function osHealth(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_health', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j.data;
}
export async function osIncidents(action: string, body: Record<string, any> = {}) {
  const { data: { session } } = await supa.auth.getSession();
  const token = session?.access_token;
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 25000);
  let r: Response;
  try {
    r = await fetch(SUPA_URL + '/functions/v1/os_incidents', { method: 'POST', signal: ctl.signal, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify({ action, ...body }) });
  } catch (e: any) { throw new Error(e?.name === 'AbortError' ? 'Request timed out — please retry' : (e?.message || 'Network error')); } finally { clearTimeout(timer); }
  const j = await r.json().catch(() => ({} as any));
  if (r.status === 401) throw new Error('Session expired');
  if (r.status === 403) throw new Error('Not authorized (admin only)');
  if (j.error) throw new Error(j.error);
  return j.data;
}
