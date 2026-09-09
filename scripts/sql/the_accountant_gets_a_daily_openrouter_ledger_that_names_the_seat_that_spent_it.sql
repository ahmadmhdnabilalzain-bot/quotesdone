-- THE ACCOUNTANT GETS A DAILY OPENROUTER LEDGER THAT NAMES THE SEAT THAT SPENT IT.
-- Agent: accountant.
--
-- The founder, 9 Sep 2026: "the accountant need to be tracking open router daily expense with a
-- breakdown of where it was used. which agent used it and for what, like a proper log."
--
-- ---------------------------------------------------------------------------------------------
-- WHAT WAS ACTUALLY BROKEN, MEASURED ON htdblwldjkcgjvmqkbeh BEFORE ANY OF THIS WAS WRITTEN.
-- ---------------------------------------------------------------------------------------------
-- The session brief said public.llm_calls holds 86 rows whose model_used, prompt_tokens and
-- output_tokens are all NULL, and concluded the call log cannot cost itself. The COUNT is right.
-- The CAUSE is not, and building on llm_calls would have been building on the wrong table.
--
--   1. llm_calls IS NOT THE LEDGER. It has exactly ONE writer left in the whole repository --
--      supabase/functions/site_assistant/index.ts:25 -- and that writer is a side-log, not the
--      accounting path. scripts/staging/seed_cost_config.mjs already calls it "a dead legacy
--      table" and repointed every monitoring view off it. The live ledger is public.ai_cost_log,
--      written by fn_llm_log from ai_gateway, which every model call in the company goes through.
--
--   2. WHY site_assistant's OWN COLUMNS ARE NULL. Read the code:
--          let usedModel: string|null = null; let usage: any = null;
--          ... usedModel = jd?.model || null;          <- assigned
--          ... await logLlm({ ..., prompt_tokens: usage?.prompt_tokens ?? null, ... })
--      `usage` is DECLARED and NEVER ASSIGNED. The gateway returns prompt_tokens, output_tokens,
--      cached_input_tokens and cost_usd in its response body; site_assistant reads none of them.
--      So those three columns were structurally null on every row that table will ever hold. That
--      is a two-line defect in one edge function, not a missing capability.
--
--   3. WHY model_used IS 'none' EVERYWHERE, INCLUDING IN ai_cost_log. ai_cost_log holds 11 rows
--      (8 Sep 02:19 UTC -> 9 Sep 01:41 UTC) and EVERY ONE of them reads model_used='none',
--      prompt_tokens=0, output_tokens=0, cost_aed=0. That is not a logging failure. It is the
--      founder's OpenRouter hold working exactly as instructed: paidProviderGate refuses every
--      route, ai_gateway takes its circuit_open branch and logs model 'none' with the rule that
--      held it. Corroborated at the provider: GET https://openrouter.ai/api/v1/key returns
--      usage_daily 0, usage_weekly 0, usage_monthly 0 against a lifetime usage of 195.92587941 USD.
--      NOTHING HAS BEEN SPENT ON OPENROUTER SINCE THE HOLD. A ledger that reported a number here
--      would be reporting a number that does not exist.
--
--   4. THE THREE THINGS THAT WERE GENUINELY MISSING, AND ARE THE REASON A LOG COULD NOT COST
--      ITSELF THE MOMENT THE HOLD LIFTS:
--        a. THE SEAT. ai_cost_log.agent_key is NULL on 11 of 11 rows. ai_gateway forwards
--           body.agent, llm.ts forwards def.agent, and of every function that reaches the gateway
--           only `accountant` and `sales_engineer` ever set it. There is no org chart to infer an
--           owner from any more (the founder removed it on 7 Sep), so the seat must be RECORDED.
--        b. THE GENERATION ID. ai_gateway reads j.choices[0] and j.usage from the OpenRouter
--           completion and throws away j.id. Without it no row can ever be reconciled against
--           OpenRouter's own per-generation record at GET /api/v1/generation?id=.
--        c. OPENROUTER'S OWN COST. cost_aed is DERIVED from public.model_rate. That is our price
--           list, not their invoice. The two can differ (provider surcharges, BYOK, mid-flight
--           price changes) and nothing recorded the difference.
--
-- ---------------------------------------------------------------------------------------------
-- WHICH OPENROUTER ENDPOINTS ANSWERED, PROBED WITH THE REAL KEY (app_secrets.openrouter_api_key)
-- ON 9 SEP 2026. Nothing below relies on an endpoint that was not called.
-- ---------------------------------------------------------------------------------------------
--   GET /api/v1/credits    -> 200  {"data":{"total_credits":210,"total_usage":195.92587941}}
--   GET /api/v1/key        -> 200  usage 195.92587941, usage_daily 0, usage_weekly 0,
--                                  usage_monthly 0, limit 200, limit_remaining 4.07412059,
--                                  is_management_key false
--   GET /api/v1/activity   -> 403  {"error":{"message":"Only management keys can fetch activity
--                                  for an account","code":403}}   <- NOT AVAILABLE TO US.
--   GET /api/v1/generation?id=<bogus> -> 404 {"error":{"message":"Generation ... not found"}}
--                                  <- the endpoint exists and answers; it needs a real id, which
--                                     is why (b) above is captured from now on.
--
-- The daily activity endpoint is the obvious source and we CANNOT USE IT: it needs a management
-- key the founder has not issued, and this file does not ask him for one. So the authoritative
-- daily figure is derived the way a utility bill is derived -- from a METER. /api/v1/credits
-- returns a monotonic lifetime total_usage; two readings either side of a day differ by exactly
-- what that day cost. That is a measurement, not an estimate, and it is exact whatever OpenRouter
-- decides a "day" is at their end. usage_daily from /api/v1/key is stored alongside it as a
-- corroborating figure, never as the primary.
--
-- ---------------------------------------------------------------------------------------------
-- THE THREE BASES, WHICH ARE THE ACCOUNTANT'S OWN RULE (ceo_standing_grant 'accountant.reporting').
-- ---------------------------------------------------------------------------------------------
--   'measured'  -- both meter readings exist and differ; the figure is their difference.
--   'true zero' -- both readings exist and are equal; the day genuinely cost nothing.
--   'unknown'   -- a reading is missing, so the day's spend CANNOT be derived. Reported as the
--                  word unknown with the reason. NEVER as 0, and never booked as an expense.
--
-- The same rule runs one level down, per call:
--   'priced'   -- OpenRouter reported a cost, or our rate card could price the recorded tokens.
--   'free'     -- model_used='none': policy answered, no provider call, genuinely nothing spent.
--   'unpriced' -- a model WAS used and no tokens/cost were recorded. Counted, never summed, and
--                 surfaced by name. This is the honest home of every historical row whose tokens
--                 were never written down: "unknown -- not recorded at the time", not zero.
--
-- ---------------------------------------------------------------------------------------------
-- AND THE DIFFERENCE IS ALWAYS ITS OWN LINE.
-- ---------------------------------------------------------------------------------------------
-- authoritative - attributed = unattributed, printed as a line of its own with the functions that
-- produced it. It is NEVER spread across the seats. A seat total that quietly absorbed the gap
-- would be a number nobody could ever check, which is the exact failure the founder's standing
-- rule about status columns describes.
--
-- SCHEDULING: Vercel cron -> /api/resilience-ping -> resilience_ping (edge), which already carries
-- the CEO digest, the rating ask, the Dropbox backup and the accountant's weekly report. This is
-- the fifth tick on that path. pg_cron is DEAD (cron.job holds one inactive row; 234 jobs deleted
-- on the founder's 7 Sep instruction) and is not used here.
-- ---------------------------------------------------------------------------------------------

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE CALL LOG LEARNS TO COST ITSELF.
-- ---------------------------------------------------------------------------------------------
alter table public.ai_cost_log
  add column if not exists generation_id     text,
  add column if not exists cost_usd_reported numeric,
  add column if not exists seat              text,
  add column if not exists seat_basis        text;

comment on column public.ai_cost_log.generation_id is
  'OpenRouter''s own id for this generation (the `id` field on the chat.completions response). The key to GET /api/v1/generation?id=, which is the only place their per-call charge can be read back. Null on every row written before 9 Sep 2026 and on every row where no provider call was made.';
comment on column public.ai_cost_log.cost_usd_reported is
  'The cost OPENROUTER reported for this call, in USD, from usage.cost on the completion response (requested with usage:{include:true}). cost_aed beside it is DERIVED from our own public.model_rate card. When both are present and they disagree, theirs is the invoice and ours is the estimate.';
comment on column public.ai_cost_log.seat is
  'Which of the four seats spent this money: ceo, customer_support, sales_engineer or accountant. Resolved at write time by fn_llm_log, never backfilled by guesswork. Deliberately NOT a foreign key to org_agents: this is a high-volume telemetry insert, and an FK to a table the founder has emptied once already would turn a seat rename into silent, total loss of the spend log. fn_llm_log checks org_agents for existence instead, and stores null when it cannot.';
comment on column public.ai_cost_log.seat_basis is
  'How the seat on this row was arrived at. declared = the calling function passed it. bound = it came from the standing declaration in llm_seat_binding. unattributed = no seat is known, and the row is reported as unattributed rather than assigned to anyone.';

do $guard$
begin
  if not exists (select 1 from pg_constraint where conname = 'ai_cost_log_seat_basis_check') then
    alter table public.ai_cost_log
      add constraint ai_cost_log_seat_basis_check
      check (seat_basis is null or seat_basis in ('declared','bound','unattributed'));
  end if;
end $guard$;

-- A generation id identifies exactly one charge at OpenRouter. Two rows carrying the same id would
-- double-count real money, so the database refuses it rather than trusting the caller.
create unique index if not exists ai_cost_log_generation_id_uidx
  on public.ai_cost_log (generation_id) where generation_id is not null;

-- The reconciliation groups by Dubai calendar day; without this every day costs a seq scan.
create index if not exists ai_cost_log_dubai_day_idx
  on public.ai_cost_log (((occurred_at at time zone 'Asia/Dubai')::date));

-- ---------------------------------------------------------------------------------------------
-- 2. THE STANDING DECLARATION OF WHO OWNS A FUNCTION'S SPEND.
--
-- A caller that knows its seat passes it and wins (seat_basis 'declared'). A caller that does not
-- gets the seat declared here (seat_basis 'bound'). Anything else is 'unattributed' and is
-- reported as such -- an unattributed dirham is a finding, and a guessed one is a lie.
--
-- Every binding below comes from a RECORDED fact, not from reading the code and forming a view:
--   * org_agents.role for sales_engineer states the seat's scope verbatim -- "inquiry intake,
--     technical scope, supplier capability and verification, matching and safe dispatch".
--   * org_agents.role for accountant -- "every financial matter on the platform".
--   * customer_support is the messaging seat (the WhatsApp agent and the homepage widget).
--   * The founder's 9 Sep ruling on the surface split: the homepage widget is Support, either
--     PORTAL is Sales. site_assistant serves both, so it is deliberately ABSENT from this table --
--     it declares its seat per request from the session it can actually see.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.llm_seat_binding (
  fn           text primary key,
  seat         text not null,
  note         text,
  declared_at  timestamptz not null default now()
);
comment on table public.llm_seat_binding is
  'The standing declaration of which seat owns the OpenRouter spend of each edge function that reaches ai_gateway. Read at write time by fn_llm_log. A function absent from here, whose caller declares no agent, produces rows the accountant reports as UNATTRIBUTED -- which is the correct answer, not a gap to be filled with a guess.';

insert into public.llm_seat_binding (fn, seat, note) values
  ('accountant',              'accountant',       'The accountant seat''s own runtime. org_agents.role: every financial matter on the platform.'),
  ('ceo_agent',               'ceo',              'The CEO seat''s own runtime.'),
  ('sales_engineer',          'sales_engineer',   'The sales engineer seat''s own runtime.'),
  ('customer_api',            'sales_engineer',   'Customer portal surface. Founder 9 Sep: either portal is Sales.'),
  ('customer_portal',         'sales_engineer',   'Customer portal surface. Founder 9 Sep: either portal is Sales.'),
  ('customer_intelligence',   'sales_engineer',   'Customer portal surface. Founder 9 Sep: either portal is Sales.'),
  ('supplier_api',            'sales_engineer',   'Supplier portal surface. Founder 9 Sep: either portal is Sales.'),
  ('supplier_portal',         'sales_engineer',   'Supplier portal surface. Founder 9 Sep: either portal is Sales.'),
  ('supplier_onboard',        'sales_engineer',   'org_agents.role: supplier capability and verification.'),
  ('supplier_catalog_ingest', 'sales_engineer',   'org_agents.role: supplier capability and verification.'),
  ('inquiry_intake',          'sales_engineer',   'org_agents.role: inquiry intake.'),
  ('quote_compare',           'sales_engineer',   'org_agents.role: technical scope, matching.'),
  ('quote_extract',           'sales_engineer',   'org_agents.role: technical scope, matching.'),
  ('license_extract',         'sales_engineer',   'org_agents.role: supplier capability and verification.'),
  ('drawing_boq',             'sales_engineer',   'org_agents.role: technical scope.'),
  ('drawing_redact',          'sales_engineer',   'org_agents.role: technical scope, safe dispatch.'),
  ('doc_extract',             'sales_engineer',   'org_agents.role: technical scope.'),
  ('extract_text',            'sales_engineer',   'org_agents.role: technical scope.'),
  ('cad_convert',             'sales_engineer',   'org_agents.role: technical scope.'),
  ('transcribe',              'sales_engineer',   'org_agents.role: technical scope.'),
  ('negotiation_assistant',   'sales_engineer',   'org_agents.role: matching and safe dispatch.'),
  ('wa_inbound',              'customer_support', 'customer_support is the WhatsApp agent.'),
  ('messages_api',            'customer_support', 'Customer/supplier messaging surface.'),
  ('email_triage',            'customer_support', 'Inbound customer mail.'),
  ('resend_inbound',          'customer_support', 'Inbound customer mail.'),
  ('inbound_email',           'customer_support', 'Inbound customer mail.'),
  ('supplier_ack',            'customer_support', 'Founder 9 Sep: supplier questions always via Support.')
on conflict (fn) do update
  set seat = excluded.seat, note = excluded.note, declared_at = now();

-- A binding to a seat that does not exist would attribute money to nobody while looking attributed.
delete from public.llm_seat_binding b
 where not exists (select 1 from public.org_agents a where a.agent_key = b.seat);

-- ---------------------------------------------------------------------------------------------
-- 3. THE METER. Two readings either side of a day are that day's bill.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.openrouter_meter (
  id                  bigserial primary key,
  read_at             timestamptz not null default now(),
  ok                  boolean not null,
  cumulative_usd      numeric,   -- /api/v1/credits -> data.total_usage  (monotonic, the meter)
  credits_total_usd   numeric,   -- /api/v1/credits -> data.total_credits
  usage_daily_usd     numeric,   -- /api/v1/key     -> data.usage_daily  (corroborating only)
  usage_monthly_usd   numeric,   -- /api/v1/key     -> data.usage_monthly
  limit_remaining_usd numeric,   -- /api/v1/key     -> data.limit_remaining
  key_label           text,
  err                 text
);
comment on table public.openrouter_meter is
  'Readings of OpenRouter''s own lifetime spend counter, taken every ~15 minutes by resilience_ping. A day''s authoritative spend is the difference between the last reading of that day and the last reading of the day before -- the way a utility bill is read. This exists because GET /api/v1/activity returns 403 "Only management keys can fetch activity for an account" with the key we hold (probed 9 Sep 2026), so the daily endpoint is not available to us. A failed reading is stored with ok=false and its error, because a gap in the meter must be visible: it is what turns a day''s basis from measured to unknown.';
create index if not exists openrouter_meter_read_at_idx on public.openrouter_meter (read_at desc);

-- ---------------------------------------------------------------------------------------------
-- 4. THE CLOSED-DAY RECONCILIATION RECORD.
--
-- This is the accountant's working paper, not a second expenses table. The MONEY lands in
-- public.expense_entries (the ledger the weekly financial report already reads, mapped through
-- gl_expense_map 'Usage' -> gl_accounts 6000 Software & AI). What lives here is everything an
-- expense row cannot carry: the basis, the attributed/unattributed split, the per-seat breakdown,
-- and the two meter readings the figure was derived from -- so any number in the report can be
-- walked back to the two readings that produced it. A day whose basis is 'unknown', and a day that
-- genuinely cost nothing, are both RECORDED here and produce NO expense row.
--
-- public.expenses was considered and is the wrong shape: it is the recurring-vendor register
-- (cadence, next_due, active, reminder_days), not a charge ledger, and it is not what the
-- accountant's weekly report sums.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.openrouter_day (
  day                 date primary key,
  authoritative_usd   numeric,
  authoritative_basis text not null,
  attributed_usd      numeric not null default 0,
  unattributed_usd    numeric,
  calls               integer not null default 0,
  calls_priced        integer not null default 0,
  calls_free          integer not null default 0,
  calls_unpriced      integer not null default 0,
  breakdown           jsonb   not null default '{}'::jsonb,
  meter_open_id       bigint,
  meter_close_id      bigint,
  expense_entry_id    bigint,
  note                text,
  reconciled_at       timestamptz not null default now()
);
comment on table public.openrouter_day is
  'One row per closed Asia/Dubai day: what OpenRouter''s meter says the day cost, what our own call log attributes to the four seats, and the difference as an explicit unattributed line. Owned by the accountant seat. The expense itself is in expense_entries; this is the working paper that proves the expense.';

do $guard$
begin
  if not exists (select 1 from pg_constraint where conname = 'openrouter_day_basis_check') then
    alter table public.openrouter_day
      add constraint openrouter_day_basis_check
      check (authoritative_basis in ('measured','true zero','unknown'));
  end if;
end $guard$;

-- One OpenRouter expense per day, ever. Without this a retried tick books the same money twice.
create unique index if not exists expense_entries_openrouter_day_uidx
  on public.expense_entries (charged_on)
  where source = 'accountant:openrouter_daily';

commit;

-- =============================================================================================
-- 5. fn_llm_log LEARNS THE THREE FACTS IT WAS NEVER TOLD.
--
--    Two new arguments, both defaulted, so the sixteen-argument call ai_gateway makes today keeps
--    working unchanged while the deployment rolls. The body is otherwise the 9 Sep body verbatim
--    (rate-card costing, the could_be_cheaper comparator and its 11 Aug rewrite, the confidence
--    normalisation) plus the seat resolution.
--
--    THE SEAT RESOLUTION IS THE POINT OF THIS FUNCTION'S CHANGE. Three sources, in order, and each
--    row records WHICH one answered so a reader can tell a declaration from a standing binding:
--      declared     the caller passed p_agent and it names a live seat
--      bound        llm_seat_binding declares the owner of this function
--      unattributed neither -- stored as NULL seat, reported as unattributed, never guessed
--
--    A p_agent that does NOT name a live seat (an old department key, a retired agent) does not
--    fall through to the binding: it is recorded on agent_key as it always was, and the seat is
--    left unattributed. Silently mapping an unknown spender onto a known one is exactly the
--    fabrication the founder's standing rule forbids.
-- =============================================================================================
begin;

create or replace function public.fn_llm_log(
  p_fn text, p_dept text, p_agent text, p_task_class text, p_model text, p_because text,
  p_tier text, p_prompt_tokens integer, p_output_tokens integer, p_cached boolean,
  p_cache_key text, p_latency_ms integer, p_ok boolean,
  p_confidence numeric default null,
  p_cached_in integer default 0,
  p_cache_write integer default 0,
  p_generation_id text default null,
  p_cost_usd_reported numeric default null)
returns numeric
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cr numeric; v_cw numeric;
        v_cheaper boolean := false; v_reason text; v_alt text; v_class text;
        v_plain int; v_read int; v_write int;
        v_alt_model text; v_alt_rate numeric; v_used_rate numeric;
        v_seat text; v_seat_basis text := 'unattributed';
begin
  v_class := coalesce(nullif(trim(coalesce(p_task_class,'')), ''), case
    when p_fn ~* 'agent_brain|dept_plan|exec_agents|reflect|conductor'   then 'agent_reasoning'
    when p_fn ~* 'cos_execute|secretary|chief'                            then 'chief_of_staff_decision'
    when p_fn ~* 'knowledge|kb_|canon_eval|research|exam'                 then 'knowledge_research'
    when p_fn ~* 'extract|parse|ocr'                                      then 'document_extraction'
    when p_fn ~* 'classif|categor|intent|route'                           then 'category_classification'
    when p_fn ~* 'draft|content|blog|marketing|social'                    then 'content_drafting'
    when p_fn ~* 'quote|rfq|supplier|procure'                             then 'procurement_reasoning'
    else 'general_drafting' end);

  -- WHO SPENT IT. Declaration first, standing binding second, honest silence third.
  if nullif(btrim(coalesce(p_agent,'')),'') is not null
     and exists (select 1 from public.org_agents a where a.agent_key = btrim(p_agent)) then
    v_seat := btrim(p_agent); v_seat_basis := 'declared';
  else
    select b.seat into v_seat from public.llm_seat_binding b where b.fn = p_fn;
    if v_seat is not null then v_seat_basis := 'bound'; else v_seat_basis := 'unattributed'; end if;
  end if;

  v_read  := greatest(coalesce(p_cached_in,0), 0);
  v_write := greatest(coalesce(p_cache_write,0), 0);
  v_plain := greatest(coalesce(p_prompt_tokens,0) - v_read - v_write, 0);

  if not coalesce(p_cached,false) then
    select in_aed_per_mtok, out_aed_per_mtok, cache_read_aed_per_mtok, cache_write_aed_per_mtok
      into v_in, v_out, v_cr, v_cw
      from model_rate where model = p_model;
    if v_in is not null then
      v_cost := round( v_plain/1000000.0 * v_in
                     + v_read /1000000.0 * coalesce(v_cr, v_in * 0.10)
                     + v_write/1000000.0 * coalesce(v_cw, v_in * 1.25)
                     + coalesce(p_output_tokens,0)/1000000.0 * v_out, 6);
    end if;
  end if;

  select deterministic_alternative into v_alt from model_policy where task_class = v_class;
  if v_alt is not null and v_alt <> '' then
    v_cheaper := true; v_reason := 'A deterministic path exists for this task class: ' || v_alt;
  elsif not coalesce(p_cached,false) then
    select mr.model, mr.in_aed_per_mtok into v_alt_model, v_alt_rate
      from model_rate mr
     where mr.in_aed_per_mtok is not null
     order by mr.in_aed_per_mtok asc
     limit 1;
    select mr.in_aed_per_mtok into v_used_rate from model_rate mr where mr.model = p_model;
    if v_alt_model is not null and v_used_rate is not null
       and v_alt_rate * 2 <= v_used_rate then
      v_cheaper := true;
      v_reason := v_alt_model || ' costs ' || round(v_used_rate / nullif(v_alt_rate,0), 1)
               || 'x less on input than ' || p_model
               || ' (' || v_alt_rate || ' vs ' || v_used_rate || ' AED/Mtok). '
               || 'Whether it is good enough for this task class is a policy decision, not a fact - '
               || 'this flag is the question, not the answer.';
    end if;
  end if;

  insert into ai_cost_log (fn, dept_key, agent_key, task_class, model_used, model_selected_because,
    tier, prompt_tokens, output_tokens, cached, cache_hit_key, latency_ms, cost_aed,
    could_be_cheaper, cheaper_reason, ok, confidence, cached_in_tokens, cache_write_tokens,
    generation_id, cost_usd_reported, seat, seat_basis)
  values (p_fn, p_dept, p_agent, v_class, p_model, p_because, p_tier,
    coalesce(p_prompt_tokens,0), coalesce(p_output_tokens,0), coalesce(p_cached,false),
    p_cache_key, p_latency_ms, v_cost, v_cheaper, v_reason, coalesce(p_ok,true),
    case when p_confidence is null then null
         when p_confidence >= 0 and p_confidence <= 1   then p_confidence
         when p_confidence > 1  and p_confidence <= 100 then round(p_confidence / 100.0, 4)
         else null end,
    v_read, v_write,
    nullif(btrim(coalesce(p_generation_id,'')),''), p_cost_usd_reported, v_seat, v_seat_basis)
  -- The generation id is unique. A retried write of the SAME provider charge must not create a
  -- second row that the reconciliation would then count twice.
  on conflict (generation_id) where generation_id is not null do nothing;

  return v_cost;
end $fn$;

-- The sixteen-argument form is dropped in the SAME transaction as the eighteen-argument form is
-- created, so no session ever sees both and no named-argument call is ever ambiguous.
drop function if exists public.fn_llm_log(text, text, text, text, text, text, text, integer,
                                          integer, boolean, text, integer, boolean, numeric,
                                          integer, integer);

-- A freshly CREATED function is granted EXECUTE to PUBLIC. This one is SECURITY DEFINER and writes
-- the spend ledger; anon must never reach it (scripts/checks/anon_cannot_execute_security_definer).
revoke execute on function public.fn_llm_log(text, text, text, text, text, text, text, integer,
                                             integer, boolean, text, integer, boolean, numeric,
                                             integer, integer, text, numeric) from public;

comment on function public.fn_llm_log(text, text, text, text, text, text, text, integer, integer,
                                      boolean, text, integer, boolean, numeric, integer, integer,
                                      text, numeric) is
  'Writes one ai_cost_log row per model request. Since 9 Sep 2026 it also records OpenRouter''s generation id, the cost OpenRouter itself reported, and WHICH SEAT spent the money - declared by the caller, else taken from the standing llm_seat_binding declaration, else left unattributed. It never guesses a seat: an unattributed dirham is reported as unattributed.';

commit;

-- =============================================================================================
-- 6. THE PER-CALL MONEY LOG. The founder asked for "a proper log", so there is one to read.
--    Deterministic view over ai_cost_log; no LLM anywhere in this path.
-- =============================================================================================
create or replace view public.v_openrouter_call_log as
select
  c.id,
  c.occurred_at,
  (c.occurred_at at time zone 'Asia/Dubai')::date            as dubai_day,
  coalesce(c.seat, '(unattributed)')                          as seat,
  coalesce(c.seat_basis, 'unattributed')                      as seat_basis,
  c.fn                                                        as used_by_function,
  c.task_class                                                as purpose,
  c.model_used,
  c.tier,
  c.prompt_tokens, c.output_tokens, c.cached_in_tokens, c.cache_write_tokens,
  c.generation_id,
  c.cost_usd_reported,
  c.cost_aed                                                  as cost_aed_rate_card,
  case
    when c.model_used = 'none' or c.cached then 'free'
    when coalesce(c.cost_usd_reported, nullif(c.cost_aed,0)) is not null then 'priced'
    else 'unpriced'
  end                                                         as cost_basis,
  case
    when c.model_used = 'none' or c.cached then 0::numeric
    when c.cost_usd_reported is not null then c.cost_usd_reported
    when coalesce(c.cost_aed,0) > 0 then round(c.cost_aed / r.fx, 6)
    else null
  end                                                         as cost_usd,
  c.ok, c.latency_ms, c.model_selected_because
from public.ai_cost_log c
-- The peg lives in ONE place. gl_settings.usd_to_aed carries the Central Bank peg and its own note
-- saying what to do if it is ever abandoned; a literal copied into a view is how that note gets
-- missed. One row, cross joined, so the planner reads it once.
cross join (select coalesce(max(num_value), 3.6725) fx
              from public.gl_settings where key = 'usd_to_aed') r;

comment on view public.v_openrouter_call_log is
  'The accountant''s per-call OpenRouter log: when, which SEAT, which function, for WHAT (purpose = task_class), on which model, how many tokens, OpenRouter''s generation id, and what it cost - with cost_basis saying priced / free / unpriced. unpriced means a model was used and the tokens were never recorded, i.e. UNKNOWN, not zero. Deterministic; no model is consulted to produce it.';

-- =============================================================================================
-- 7. THE DAY'S BREAKDOWN. By seat, by purpose, by model, by seat-and-purpose - counts and cost.
--    Pure read. Deterministic SQL, exactly as the founder required for a task of this kind.
-- =============================================================================================
create or replace function public.fn_accountant_openrouter_breakdown(p_day date)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $brk$
-- A GROUP WHOSE CALLS ARE ALL UNPRICED HAS AN UNKNOWN COST, NOT A ZERO ONE.
-- Caught by the 9 Sep probe: sales_engineer/document_extraction printed "0.000000 USD" for a single
-- call that used a model and recorded no tokens. Read off a report that is a claim the seat spent
-- nothing on document extraction that day, which is precisely the fabrication the founder's
-- standing rule forbids. Every group therefore reports usd/aed as NULL when it holds no priced
-- call and at least one unpriced one, and every group carries its own unpriced COUNT so an unknown
-- is visible rather than silent. sum() ignoring nulls does the rest: an unpriced call can never
-- inflate or deflate a total, and the money it did cost lands in the unattributed line against
-- OpenRouter's own meter, where it belongs.
with fx as (
  select coalesce(max(num_value), 3.6725) v from public.gl_settings where key = 'usd_to_aed'
),
rows as (
  select * from public.v_openrouter_call_log where dubai_day = p_day
),
tot as (
  select count(*)::int calls,
         count(*) filter (where cost_basis = 'priced')::int   priced,
         count(*) filter (where cost_basis = 'free')::int     free,
         count(*) filter (where cost_basis = 'unpriced')::int unpriced,
         coalesce(sum(cost_usd),0)::numeric                    usd
    from rows
),
by_seat as (
  select jsonb_agg(x order by x->>'seat') j from (
    select jsonb_build_object(
      'seat', seat, 'seat_basis', min(seat_basis),
      'calls', count(*)::int,
      'priced', count(*) filter (where cost_basis='priced')::int,
      'free', count(*) filter (where cost_basis='free')::int,
      'unpriced', count(*) filter (where cost_basis='unpriced')::int,
      'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end,
      'aed', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0) * (select v from fx), 2) end) x
    from rows group by seat) s
),
by_purpose as (
  select jsonb_agg(x order by x->>'purpose') j from (
    select jsonb_build_object('purpose', coalesce(purpose,'(unclassified)'),
      'calls', count(*)::int, 'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end,
      'aed', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0) * (select v from fx), 2) end,
      'unpriced', count(*) filter (where cost_basis='unpriced')::int) x
    from rows group by coalesce(purpose,'(unclassified)')) s
),
by_model as (
  select jsonb_agg(x order by x->>'model') j from (
    select jsonb_build_object('model', coalesce(model_used,'(none)'),
      'calls', count(*)::int, 'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end,
      'aed', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0) * (select v from fx), 2) end,
      'prompt_tokens', coalesce(sum(prompt_tokens),0)::bigint,
      'output_tokens', coalesce(sum(output_tokens),0)::bigint,
      'unpriced', count(*) filter (where cost_basis='unpriced')::int) x
    from rows group by coalesce(model_used,'(none)')) s
),
by_seat_purpose as (
  select jsonb_agg(x order by x->>'seat', x->>'purpose') j from (
    select jsonb_build_object('seat', seat, 'purpose', coalesce(purpose,'(unclassified)'),
      'calls', count(*)::int, 'unpriced', count(*) filter (where cost_basis='unpriced')::int, 'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end,
      'aed', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0) * (select v from fx), 2) end) x
    from rows group by seat, coalesce(purpose,'(unclassified)')) s
),
unattributed_fns as (
  select jsonb_agg(x order by x->>'fn') j from (
    select jsonb_build_object('fn', used_by_function, 'calls', count(*)::int,
      'usd', case when count(*) filter (where cost_basis='priced') = 0 and count(*) filter (where cost_basis='unpriced') > 0 then null else round(coalesce(sum(cost_usd),0),6) end) x
    from rows where seat = '(unattributed)' group by used_by_function) s
)
select jsonb_build_object(
  'day', p_day,
  'timezone', 'Asia/Dubai',
  'calls', (select calls from tot),
  'calls_priced', (select priced from tot),
  'calls_free', (select free from tot),
  'calls_unpriced', (select unpriced from tot),
  'attributed_usd', round((select usd from tot), 6),
  'attributed_aed', round((select usd from tot) * (select v from fx), 2),
  'unpriced_note', case when (select unpriced from tot) > 0
      then (select unpriced from tot)::text || ' call(s) used a model and no tokens or provider cost '
           || 'were recorded at the time. Their cost is UNKNOWN -- not recorded at the time -- and is '
           || 'deliberately excluded from attributed_usd rather than counted as zero. They show in '
           || 'the unattributed line against OpenRouter''s own meter.'
      else null end,
  'by_seat', coalesce((select j from by_seat), '[]'::jsonb),
  'by_purpose', coalesce((select j from by_purpose), '[]'::jsonb),
  'by_model', coalesce((select j from by_model), '[]'::jsonb),
  'by_seat_and_purpose', coalesce((select j from by_seat_purpose), '[]'::jsonb),
  'unattributed_functions', coalesce((select j from unattributed_fns), '[]'::jsonb));
$brk$;

revoke execute on function public.fn_accountant_openrouter_breakdown(date) from public;

comment on function public.fn_accountant_openrouter_breakdown(date) is
  'The accountant''s deterministic breakdown of one Asia/Dubai day of OpenRouter usage: by seat, by purpose, by model, and by seat-and-purpose, with counts and cost. Reports only what our own log attributes; the authoritative provider total and the unattributed difference come from fn_accountant_openrouter_tick. Contains no model call of any kind.';

-- =============================================================================================
-- 8. THE TICK. One reading in, closed days reconciled and booked out.
--    Called by resilience_ping every ~15 minutes on the LIVE (Vercel cron) scheduler.
-- =============================================================================================
create or replace function public.fn_accountant_openrouter_tick(p_reading jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $tick$
declare
  v_tz     constant text := 'Asia/Dubai';
  v_fx     numeric;
  v_today  date := (now() at time zone v_tz)::date;
  v_meter  bigint;
  v_day    date;
  v_open   public.openrouter_meter%rowtype;
  v_close  public.openrouter_meter%rowtype;
  v_auth   numeric;
  v_basis  text;
  v_note   text;
  v_brk    jsonb;
  v_attr   numeric;
  v_exp    bigint;
  v_done   jsonb := '[]'::jsonb;
  v_n      int := 0;
begin
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed';
  v_fx := coalesce(v_fx, 3.6725);

  -- ---- the reading -------------------------------------------------------------------------
  -- Stored whether or not it succeeded. A failed reading is the record that turns a day's basis
  -- from measured to unknown; dropping it would let a gap look like a quiet day.
  if p_reading ? 'ok' then
    insert into public.openrouter_meter
      (ok, cumulative_usd, credits_total_usd, usage_daily_usd, usage_monthly_usd,
       limit_remaining_usd, key_label, err)
    values (
      coalesce((p_reading->>'ok')::boolean, false),
      nullif(p_reading->>'cumulative_usd','')::numeric,
      nullif(p_reading->>'credits_total_usd','')::numeric,
      nullif(p_reading->>'usage_daily_usd','')::numeric,
      nullif(p_reading->>'usage_monthly_usd','')::numeric,
      nullif(p_reading->>'limit_remaining_usd','')::numeric,
      nullif(p_reading->>'key_label',''),
      left(nullif(p_reading->>'err',''), 500))
    returning id into v_meter;
  end if;

  -- ---- close every past day that has evidence and no record yet ------------------------------
  -- "Evidence" is a meter reading or a logged call. A day with neither never existed for us and is
  -- not invented. Capped at 60 days so a first run cannot walk the whole history in one tick.
  for v_day in
    select d from (
      select distinct (read_at at time zone v_tz)::date d from public.openrouter_meter
      union
      select distinct (occurred_at at time zone v_tz)::date from public.ai_cost_log
    ) s
    where d < v_today
      and d >= v_today - 60
      and not exists (select 1 from public.openrouter_day o where o.day = d)
    order by d
  loop
    -- The meter either side of the day. open = the last good reading BEFORE the day began;
    -- close = the last good reading taken DURING the day.
    select * into v_open from public.openrouter_meter
      where ok and cumulative_usd is not null
        and read_at < (v_day::timestamp at time zone v_tz)
      order by read_at desc limit 1;
    select * into v_close from public.openrouter_meter
      where ok and cumulative_usd is not null
        and read_at >= (v_day::timestamp at time zone v_tz)
        and read_at <  ((v_day + 1)::timestamp at time zone v_tz)
      order by read_at desc limit 1;

    if v_open.id is null or v_close.id is null then
      v_auth  := null;
      v_basis := 'unknown';
      v_note  := 'UNKNOWN -- not recorded at the time. '
              || case when v_open.id is null and v_close.id is null
                        then 'No OpenRouter meter reading exists either side of this day'
                      when v_open.id is null
                        then 'No OpenRouter meter reading exists from before this day began'
                      else 'No OpenRouter meter reading was taken during this day' end
              || ', so the day''s provider spend cannot be derived and is NOT reported as zero. '
              || 'The meter began on ' || coalesce((select min((read_at at time zone v_tz)::date)::text
                                                     from public.openrouter_meter), 'never')
              || '; GET /api/v1/activity is 403 for a non-management key, so no back-fill is possible.';
    elsif v_close.cumulative_usd < v_open.cumulative_usd then
      v_auth  := null;
      v_basis := 'unknown';
      v_note  := 'UNKNOWN -- OpenRouter''s lifetime usage counter went BACKWARDS across this day ('
              || v_open.cumulative_usd || ' -> ' || v_close.cumulative_usd || '), which a monotonic '
              || 'meter cannot do. The key was probably rotated or the account changed. Reported as '
              || 'unknown rather than as a negative or a zero.';
    else
      v_auth  := v_close.cumulative_usd - v_open.cumulative_usd;
      v_basis := case when v_auth = 0 then 'true zero' else 'measured' end;
      v_note  := 'Meter reading #' || v_open.id || ' (' || v_open.read_at || ', '
              || v_open.cumulative_usd || ' USD lifetime) to #' || v_close.id || ' ('
              || v_close.read_at || ', ' || v_close.cumulative_usd || ' USD lifetime).';
    end if;

    v_brk  := public.fn_accountant_openrouter_breakdown(v_day);
    v_attr := coalesce((v_brk->>'attributed_usd')::numeric, 0);

    -- The expense is booked ONLY on a day whose provider spend was actually measured and is
    -- non-zero. An unknown day and a true-zero day are both recorded above and book nothing:
    -- a general ledger must never carry a figure nobody can walk back to a reading.
    v_exp := null;
    if v_basis = 'measured' and v_auth > 0 then
      insert into public.expense_entries
        (vendor, category, amount, currency, charged_on, note, source)
      values ('OpenRouter', 'Usage', round(v_auth * v_fx, 2), 'AED', v_day,
        'OpenRouter model usage, ' || v_day || ' (Asia/Dubai). ' || round(v_auth,6) || ' USD at '
        || v_fx || ' = ' || round(v_auth * v_fx, 2) || ' AED. Attributed to seats: '
        || round(v_attr, 6) || ' USD. Unattributed: ' || round(v_auth - v_attr, 6) || ' USD. '
        || 'Basis: measured from the OpenRouter meter. ' || v_note
        || ' Full per-seat breakdown in public.openrouter_day for this date.',
        'accountant:openrouter_daily')
      on conflict (charged_on) where source = 'accountant:openrouter_daily'
        do update set amount = excluded.amount, note = excluded.note
      returning id into v_exp;
    end if;

    insert into public.openrouter_day
      (day, authoritative_usd, authoritative_basis, attributed_usd, unattributed_usd,
       calls, calls_priced, calls_free, calls_unpriced, breakdown,
       meter_open_id, meter_close_id, expense_entry_id, note)
    values (v_day, v_auth, v_basis, v_attr,
      case when v_auth is null then null else round(v_auth - v_attr, 6) end,
      coalesce((v_brk->>'calls')::int, 0),
      coalesce((v_brk->>'calls_priced')::int, 0),
      coalesce((v_brk->>'calls_free')::int, 0),
      coalesce((v_brk->>'calls_unpriced')::int, 0),
      v_brk, v_open.id, v_close.id, v_exp, v_note)
    on conflict (day) do nothing;

    v_n := v_n + 1;
    v_done := v_done || jsonb_build_object(
      'day', v_day, 'basis', v_basis,
      'authoritative_usd', v_auth, 'attributed_usd', round(v_attr,6),
      'unattributed_usd', case when v_auth is null then null else round(v_auth - v_attr,6) end,
      'expense_entry_id', v_exp);
  end loop;

  return jsonb_build_object(
    'ok', true, 'agent', 'accountant', 'meter_reading_id', v_meter,
    'today_dubai', v_today, 'days_reconciled', v_n, 'days', v_done);
end;$tick$;

revoke execute on function public.fn_accountant_openrouter_tick(jsonb) from public;

comment on function public.fn_accountant_openrouter_tick(jsonb) is
  'The accountant''s daily OpenRouter reconciliation, called by resilience_ping on the LIVE (Vercel cron) scheduler every ~15 minutes. Records one meter reading, then closes every past Asia/Dubai day that has evidence and no record: authoritative provider spend from the meter difference, attributed spend from our own call log by seat, and the difference as an explicit unattributed line that is NEVER absorbed into a seat. Books a measured, non-zero day into expense_entries (category Usage -> GL 6000 Software & AI); an unknown or true-zero day is recorded and books nothing. Idempotent per day. Not a pg_cron job: cron.job was emptied on the founder''s 7 Sep 2026 instruction and would not fire.';

-- =============================================================================================
-- 9. THE CLOSING ASSERTION. Every claim this file makes, checked against the database it made it in.
-- =============================================================================================
do $check$
declare
  v_missing text := '';
  v_n int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='ai_cost_log' and column_name='seat')
    then v_missing := v_missing || 'ai_cost_log.seat; '; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='ai_cost_log' and column_name='generation_id')
    then v_missing := v_missing || 'ai_cost_log.generation_id; '; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema='public' and table_name='ai_cost_log' and column_name='cost_usd_reported')
    then v_missing := v_missing || 'ai_cost_log.cost_usd_reported; '; end if;
  if to_regclass('public.openrouter_meter') is null then v_missing := v_missing || 'openrouter_meter; '; end if;
  if to_regclass('public.openrouter_day')   is null then v_missing := v_missing || 'openrouter_day; '; end if;
  if to_regclass('public.llm_seat_binding') is null then v_missing := v_missing || 'llm_seat_binding; '; end if;

  select count(*) into v_n from public.llm_seat_binding;
  if v_n = 0 then v_missing := v_missing || 'llm_seat_binding is EMPTY (every binding named a seat that does not exist); '; end if;

  -- Exactly one fn_llm_log. Two overloads would make every named-argument call ambiguous.
  select count(*) into v_n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.proname='fn_llm_log';
  if v_n <> 1 then v_missing := v_missing || 'fn_llm_log has ' || v_n || ' overloads, expected 1; '; end if;

  if v_missing <> '' then
    raise exception 'THE FILE DID NOT LAND: %', v_missing;
  end if;
  raise notice 'openrouter daily ledger: schema, bindings (%), fn_llm_log(18), breakdown, tick and view all present',
    (select count(*) from public.llm_seat_binding);
end $check$;

