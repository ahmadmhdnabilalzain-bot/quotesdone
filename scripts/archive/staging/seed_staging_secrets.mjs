// seed_staging_secrets.mjs — give staging the configuration it needs, minus the power to act.
//
// WHY THIS EXISTS
// Third-party credentials in QuotesDone are not Vercel env vars and not Supabase Edge Function
// secrets. They are rows in public.app_secrets. Production holds 194; staging held 0, which is
// why nothing in staging could run. This copies production's rows into staging.
//
// WHAT IT REFUSES TO COPY
// A staging database holding a live Vercel deploy token is a staging environment that deploys to
// production. The same argument applies to the GitHub token, the Dropbox credentials that address
// production supplier documents, and the Twilio credentials that message real people. Those are
// withheld by name, and the reason travels with the name.
//
// Outbound "blast" flags are forced off so staging boots inert: it cannot email, message, invite
// or autonomously execute until each capability is deliberately re-enabled behind an allowlist.
//
//   node seed_staging_secrets.mjs [--apply]
//
// Without --apply it reports and writes nothing. It prints key NAMES and actions only, never a value.
import { mgmtRead, mgmtWrite, PROD_REF, resolveStagingRef } from '../../lib/qd_guard.mjs';

// 15 AUG 2026: this tool's whole job is standing a SECOND project up from this one, and there is
// no second project — pglpqrhvozwepymcuunn was deleted. It is kept rather than retired because it
// works unchanged the day a new staging project exists; it now REFUSES instead of defaulting to a
// ref that 404s, because a sync reporting success against nothing is the worst outcome available.
const REF = resolveStagingRef(process.env.QD_STAGING_REF);
const STAGING = REF;
const APPLY = process.argv.includes('--apply');

const WITHHOLD = new Map([
  ['vercel_token',              'staging would deploy to the production domain'],
  ['vercel_project',            'pairs with vercel_token'],
  ['vercel_team_id',            'pairs with vercel_token'],
  ['github_token',              'staging would push to the real repository'],
  ['dropbox_app_key',           'addresses production supplier documents'],
  ['dropbox_app_secret',        'addresses production supplier documents'],
  ['dropbox_oauth_key',         'addresses production supplier documents'],
  ['dropbox_refresh_token',     'addresses production supplier documents'],
  ['dropbox_roots',             'points at production folders'],
  ['twilio_account_sid',        'real SMS/WhatsApp to real numbers'],
  ['twilio_api_key_sid',        'real SMS/WhatsApp to real numbers'],
  ['twilio_api_key_secret',     'real SMS/WhatsApp to real numbers'],
  ['twilio_from',               'real SMS/WhatsApp to real numbers'],
  ['twilio_wa_from',            'real SMS/WhatsApp to real numbers'],
  ['twilio_verify_service_sid', 'real SMS/WhatsApp to real numbers'],
  // qa_customer_password was withheld here until 22 Sep 2026, when it was deleted from production
  // altogether (scripts/sql/five_dead_secrets_leave_the_store.sql): a plaintext account password
  // nothing read. A withhold list naming a key that no longer exists is an index pointing at
  // nothing, so the entry goes with it.
]);

const FORCE_OFF = {
  email_enabled: 'false', supplier_emails_enabled: 'false',
  wa_autoreply_enabled: 'false', invite_enabled: 'false', bd_outreach_enabled: 'false',
  // meta_sync_enabled left this list on 22 Sep 2026 with the deleted key: it switched an edge
  // function (meta_sync) that no longer exists. social_send_enabled is the live social switch.
  marketing_golive: 'false', social_send_enabled: 'off', agent_autonomy_enabled: 'false',
  cos_frozen: 'true', qa_mint_enabled: 'false',
};

const rows = await mgmtRead(PROD_REF, 'select key, value from public.app_secrets order by key');
console.log(`production app_secrets: ${rows.length}`);

const copied = [], withheld = [], forced = [], guardRefused = [], payload = [];

// A rule, not a list: production's stripe_secret_key and stripe_publishable_key are LIVE keys.
// Staging holding a live payment credential can take real money, which the staging policy forbids
// outright. Match on the vendor's own live-mode prefix so a key added later is caught too.
const isLiveVendorKey = (v) => typeof v === 'string' && /^(sk|pk|rk)_live/.test(v);

for (const { key, value } of rows) {
  if (WITHHOLD.has(key)) { withheld.push([key, WITHHOLD.get(key)]); continue; }
  if (isLiveVendorKey(value)) {
    withheld.push([key, 'LIVE vendor key - staging must use test mode only']);
    continue;
  }
  // qd_guard would refuse these anyway; naming them here makes the refusal legible.
  if (typeof value === 'string' && value.includes(PROD_REF)) {
    guardRefused.push([key, 'value embeds the production project ref']);
    continue;
  }
  if (Object.prototype.hasOwnProperty.call(FORCE_OFF, key)) {
    payload.push([key, FORCE_OFF[key]]); forced.push(key); continue;
  }
  payload.push([key, value]); copied.push(key);
}

// Mode indicator derived from the key prefix. Never prints the secret.
const modeOf = (k) => {
  const v = rows.find(x => x.key === k)?.value;
  if (typeof v !== 'string') return 'absent';
  if (/^(sk|pk|rk)_live/.test(v)) return 'LIVE';
  if (/^(sk|pk|rk)_test/.test(v)) return 'test';
  return 'unrecognised-prefix';
};
console.log(`\nstripe_secret_key      : ${modeOf('stripe_secret_key')}`);
console.log(`stripe_publishable_key : ${modeOf('stripe_publishable_key')}`);

console.log(`\ncopied     : ${copied.length}`);
console.log(`forced off : ${forced.length}  ${forced.join(', ')}`);
console.log(`withheld   : ${withheld.length}`);
for (const [k, why] of withheld) console.log(`   ${k.padEnd(28)} ${why}`);
console.log(`guard refused (production ref in value): ${guardRefused.length}`);
for (const [k, why] of guardRefused) console.log(`   ${k.padEnd(28)} ${why}`);

if (!APPLY) { console.log('\nDRY RUN - nothing written. Re-run with --apply.'); process.exit(0); }

const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;

// Only write what actually differs. Some keys are protected by triggers: fn_autonomy_control_guard
// refuses to WIDEN agent_autonomy_from without `set local app.change_reason`, which a PostgREST
// call cannot do - deliberately, because that key was reachable by all 190 service-role functions.
// Re-writing an identical value would trip that guard for no reason and abort the whole seed.
const existing = new Map((await mgmtRead(STAGING, 'select key, value from public.app_secrets'))
  .map(r => [r.key, r.value]));
const changed = payload.filter(([k, v]) => existing.get(k) !== (v ?? ''));
console.log(`\n${changed.length} of ${payload.length} key(s) differ from staging and will be written`);

if (changed.length) {
  await mgmtWrite(STAGING,
    `insert into public.app_secrets (key, value) values ${changed.map(([k, v]) => `(${lit(k)}, ${lit(v ?? '')})`).join(',')}
     on conflict (key) do update set value = excluded.value`, 'seed app_secrets');
}

const after = await mgmtRead(STAGING, 'select count(*) as n from public.app_secrets');
console.log(`\nstaging app_secrets now: ${after[0].n} keys`);

// ---- internal_credential -----------------------------------------------------------------------
// app_secrets holds the credential VALUES; public.internal_credential is the registry that says
// which context each one belongs to and what it is scoped to reach. fn_internal_auth checks the
// registry, so with 74 rows in production and 0 in staging every function-to-function call was
// refused: create_inquiry reported routing {"error":"forbidden","fallback":true} and every RFQ
// produced zero supplier fits, which the system then miscounts as a supply coverage gap.
// Only the hash is copied - never a plaintext secret - and usage counters start clean.
const creds = await mgmtRead(PROD_REF,
  `select context, label, secret_hash, scope, is_legacy, active, expires_at
   from public.internal_credential order by id`);
const arr = (a) => Array.isArray(a) ? `ARRAY[${a.map(x => lit(x)).join(',')}]::text[]` : `'{}'::text[]`;
const credVals = creds.map(c => `(${[
  lit(c.context), c.label === null ? 'null' : lit(c.label), lit(c.secret_hash), arr(c.scope),
  c.is_legacy ? 'true' : 'false', c.active ? 'true' : 'false',
  c.expires_at === null ? 'null' : lit(c.expires_at),
].join(',')})`).join(',');

// This INSERT has no ON CONFLICT and internal_credential has no unique key on context, so running
// the script twice would DOUBLE every credential and leave fn_internal_auth choosing between
// duplicate rows. Only load into an empty table; the scope additions below are the supported way to
// change an existing one.
const credExisting = Number((await mgmtRead(STAGING,
  'select count(*)::int as n from public.internal_credential'))[0].n);
if (credVals && credExisting === 0) {
  await mgmtWrite(STAGING,
    `insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active, expires_at)
     values ${credVals}`, 'seed internal_credential');
} else if (credExisting > 0) {
  console.log(`internal_credential already holds ${credExisting} row(s) - skipping the bulk copy ` +
              '(re-inserting would duplicate every credential)');
}
const credAfter = await mgmtRead(STAGING, 'select count(*) as n from public.internal_credential');
console.log(`staging internal_credential now: ${credAfter[0].n} rows (production has ${creds.length})`);

// ---- scope additions staging is AHEAD of production on -------------------------------------------
// Applied after the copy so a staging rebuild reapplies them. Each one must also be promoted to
// production, and is listed in docs/archive/sessions/NEXT_SESSION_BRIEF.md §8 for exactly that reason.
//
// capability_agent: its `confirm` action is the only real writer of a confirmed
// supplier_capabilities row plus its supplier_capability_confirmation ledger entry, and it makes NO
// model call - the single model call in that function is on the `analyze` path. But no credential
// in EITHER project scopes capability_agent, so the one half of the capability flow that is not
// blocked by fn_ai_route's supplier_matching tier=none policy was unreachable anyway. Scoped to
// db.internal, which already carries its sibling enrich_capability and dispatch_inquiry.
const SCOPE_ADDITIONS = [
  ['db.internal', 'capability_agent'],
];
for (const [context, scope] of SCOPE_ADDITIONS) {
  const r = await mgmtWrite(STAGING,
    `update public.internal_credential
        set scope = (select array(select distinct unnest(coalesce(scope,'{}'::text[]) || ${lit(scope)}::text)))
      where context = ${lit(context)} and not (${lit(scope)} = any(coalesce(scope,'{}'::text[])))
      returning context`, 'scope addition');
  console.log(`scope addition: ${context} += ${scope} ${r.length ? '(added)' : '(already present)'}`);
}
