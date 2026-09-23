// model_policy_by_identity is the second table fn_ai_route reads. A row here is a route, so a row
// naming an identity no live seat can pass, or a model the catalogue does not carry, is a route
// that either cannot be taken or silently becomes a different model.
//
// Measured 23 Sep 2026, before the fix: 122 rows, 3 of which resolved to a live seat. The other 119
// named the organisation deleted on 7 Sep. Five model ids appeared in neither model_registry nor
// llm_route_health, and fn_ai_route SUBSTITUTES for an unregistered model, writing the warning into
// a `why` nothing reads.
//
// This check fails on that original input.
import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { sql } from '../lib/db.mjs';

// Runs against production only; without a management token there is nothing to read.
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';

test('every identity the router can route names a live seat', { skip: SKIP }, async () => {
  const rows = await sql(
    `select i.identity_key, i.scope
       from public.model_policy_by_identity i
      where not exists (select 1 from public.org_agents a where a.agent_key = i.identity_key)
      order by 1`,
    { readOnly: true },
  );
  assert.deepEqual(
    rows.map((r) => `${r.scope}:${r.identity_key}`),
    [],
    'these identities are not live seats, so nothing can ever pass their agent key — the rows are routes nobody can take',
  );
});

test('every model the router can name is in the catalogue and under the hold', { skip: SKIP }, async () => {
  const rows = await sql(
    `select distinct m as model,
            (select count(*) from public.model_registry r where r.model_id = m) as in_registry,
            (select count(*) from public.llm_route_health h where h.model_id = m) as in_health
       from public.model_policy_by_identity i,
            lateral unnest(array[i.primary_model, i.fallback_model, i.escalation_model]) m
      where m is not null and m <> 'none/deterministic'
        and (not exists (select 1 from public.model_registry r where r.model_id = m)
          or not exists (select 1 from public.llm_route_health h where h.model_id = m))
      order by 1`,
    { readOnly: true },
  );
  assert.deepEqual(
    rows.map((r) => r.model),
    [],
    'fn_ai_route substitutes for a model missing from model_registry and says so only in a `why` nothing reads; a model missing from llm_route_health is outside the founder\'s hold',
  );
});

test('the guard that keeps it that way is in force', { skip: SKIP }, async () => {
  const rows = await sql(
    `select tgname from pg_trigger
      where tgrelid = 'public.model_policy_by_identity'::regclass
        and tgname = 'trg_identity_policy_is_a_live_seat_and_a_known_model'
        and not tgisinternal`,
    { readOnly: true },
  );
  assert.equal(rows.length, 1, 'without the trigger the next import of a package can put the 119 dead rows back');
});
