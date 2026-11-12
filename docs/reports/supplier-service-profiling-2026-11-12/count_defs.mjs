// READ ONLY: how many service rows does supplier_trade_choice.tradeDefs's own query return? (the same select, order and client)
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
const REPO = '/tmp/claude-0/main-base';
const { keys, REF } = await import(pathToFileURL(join(REPO, 'scripts/lib/demo_factory.mjs')).href);
const { createClient } = createRequire(join(REPO, 'package.json'))('@supabase/supabase-js');
const { SERVICE } = await keys();
const admin = createClient(`https://${REF}.supabase.co`, SERVICE, { auth: { persistSession: false } });
const { data: s, error } = await admin.from('taxonomy_trade_service').select('trade_code,code,label_en,active,sort').order('sort');
const { count } = await admin.from('taxonomy_trade_service').select('*', { count: 'exact', head: true });
const got = new Set((s || []).map((r) => r.trade_code + '.' + r.code));
console.log(JSON.stringify({ error: error?.message ?? null, returned: s?.length, in_table: count, max_sort_returned: Math.max(...(s || []).map((r) => r.sort ?? 0)),
  has: Object.fromEntries(['landscaping.maintenance', 'landscaping.artificial_grass', 'landscaping.pools', 'cleaning.ac_duct', 'it_services.colocation', 'interior_fitout.refurbishment', 'labour_supply.supervisors', 'facilities_management.building_maintenance'].map((k) => [k, got.has(k)])) }));
const { data: all } = await admin.from('taxonomy_trade_service').select('trade_code,code,sort').order('sort').range(1000, 1999);
console.log('cut off (rows 1001+):', (all || []).length, (all || []).map((r) => r.trade_code + '.' + r.code).join(', '));
