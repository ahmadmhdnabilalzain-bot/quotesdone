-- V3 REMEDIATION — STAGE 2: TOOL CONNECTIVITY
-- Result of record V3-COR-0A782DA90B10 recorded TOOL_NOT_CONNECTED on 2,284 of 2,284 questions:
-- tool_calls non-empty on every execution row, tool_results empty on every execution row.
--
-- The cause was NOT a missing tool layer. ai_gateway has always accepted and forwarded OpenAI-shape
-- tools, and org_action_executor has held 59 active write executors with timeout/retry/compensation
-- columns. What was missing is the thing in between: a registry that says WHICH tool a given role
-- may invoke, WHAT its arguments look like, and a ledger proving a result actually came back.
--
-- This file adds exactly that, and nothing else. It does not invent tools. Every seeded read tool
-- wraps a routine that already exists and is already callable:
--   fn_query_platform(topic, args)          21 live topics across the company
--   fn_ops_knowledge_search(dept, q, limit) V3 operational knowledge
--   fn_dept_library_search(dept, q, limit)  department library
--   fn_ws_supplier_360(id)                  supplier dossier
--   fn_agent_handoff_inbox(agent_key)       inbound cross-department work
-- Write tools are NOT seeded here: they must route through org_action_executor so the existing
-- authority guard, idempotency strategy and compensation action keep governing them.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE REGISTRY
-- ---------------------------------------------------------------------------------------------
create table if not exists public.agent_tool (
  tool_id                text primary key,
  purpose                text not null,
  kind                   text not null default 'read'
                           check (kind in ('read','write')),
  -- write tools MUST name an executor; that is where authority, idempotency and compensation live
  action_class           text references public.org_action_executor(action_class),
  impl_kind              text not null default 'rpc'
                           check (impl_kind in ('rpc','edge_function','executor')),
  impl_target            text not null,              -- routine name or edge function slug
  -- authorisation. '*' in either array means "any"; both are ANDed when both are non-empty.
  authorised_roles       text[] not null default '{}',
  authorised_departments text[] not null default '{}',
  min_authority          text not null default 'advisory'
                           check (min_authority in ('advisory','gated','supervised','autonomous')),
  required_credential    text,                       -- app_secrets key, null = service role only
  staging_available      boolean not null default true,
  production_available   boolean not null default false,
  input_schema           jsonb not null default '{"type":"object","properties":{},"additionalProperties":false}'::jsonb,
  output_schema          jsonb not null default '{"type":"object"}'::jsonb,
  timeout_seconds        integer not null default 15 check (timeout_seconds between 1 and 120),
  max_attempts           integer not null default 2  check (max_attempts between 1 and 5),
  backoff                text not null default 'exponential_2s'
                           check (backoff in ('none','fixed_1s','exponential_2s')),
  -- what the runtime does when the tool cannot answer. fail_closed = the task stops, it does not
  -- proceed on a guess. This is the setting that turns TOOL_NOT_CONNECTED into a visible failure
  -- instead of an answer written from prompt memory.
  failure_behaviour      text not null default 'fail_closed'
                           check (failure_behaviour in ('fail_closed','escalate','degrade_with_caveat')),
  audit_behaviour        text not null default 'trace'
                           check (audit_behaviour in ('trace','trace_and_notify')),
  requires_current_data  boolean not null default true,
  stub_permitted         boolean not null default false,
  active                 boolean not null default true,
  note                   text,
  created_at             timestamptz not null default now()
);
comment on table public.agent_tool is
  'V3 remediation: which tool each role may invoke, and how it must behave. A tool absent from this table cannot be called by any agent.';
comment on column public.agent_tool.stub_permitted is
  'False everywhere by default. A stub that answers like a live tool is the defect the certification found; a stub is only ever allowed where the note says why.';

-- ---------------------------------------------------------------------------------------------
-- 2. THE LEDGER — this is what makes a fabricated tool result detectable
-- ---------------------------------------------------------------------------------------------
create table if not exists public.agent_tool_call (
  id             uuid primary key default gen_random_uuid(),
  correlation_id uuid not null,
  agent_key      text not null,
  role_id        text,
  tool_id        text not null,
  args           jsonb not null default '{}'::jsonb,
  -- ok      : the tool ran and returned rows
  -- ok_empty: the tool ran and legitimately returned nothing  <- NOT the same as a failure
  -- error / timeout / unavailable / unauthorised: the tool did not answer
  status         text not null
                   check (status in ('ok','ok_empty','error','timeout','unavailable','unauthorised')),
  result_hash    text,                       -- sha256 of the exact bytes handed to the model
  result_rows    integer,
  result_bytes   integer,
  error          text,
  attempt        integer not null default 1,
  latency_ms     integer,
  created_at     timestamptz not null default now()
);
create index if not exists agent_tool_call_corr_idx on public.agent_tool_call (correlation_id);
create index if not exists agent_tool_call_tool_idx on public.agent_tool_call (tool_id, created_at desc);
create index if not exists agent_tool_call_agent_idx on public.agent_tool_call (agent_key, created_at desc);
comment on table public.agent_tool_call is
  'Every tool invocation, including the ones that failed. result_hash is the digest of the exact bytes injected into the model conversation, so a claimed result with no matching row is provably fabricated.';

alter table public.agent_tool enable row level security;
alter table public.agent_tool_call enable row level security;

-- ---------------------------------------------------------------------------------------------
-- 3. ELIGIBILITY — deterministic, not model-decided
-- ---------------------------------------------------------------------------------------------
-- Returns the tools this agent is allowed to hold. Callers pass the agent key; the role and
-- department come from the roster, so a prompt cannot widen its own tool set.
--
-- THIS FILE COULD NOT BE RE-APPLIED, AND THAT BLOCKED THREE OTHERS (14 Aug 2026).
-- v3_repair_14_tool_credential adds required_credential to this function's return type, so on any
-- project where 14 has run, the live fn_agent_tools returns 12 columns and this 11-column CREATE OR
-- REPLACE is refused: "cannot change return type of existing function". Re-running this file then
-- aborted before it reached the agent_tool and agent_tool_call TABLES - which is why production had
-- neither, and why v3_repair_08, 09 and 14 each failed there on a missing relation rather than on
-- anything of their own. One stale signature held four files out of production.
--
-- v3_repair_14 already drops before it creates, for exactly this reason. This is the same line, so
-- that 01 -> ... -> 14 applies cleanly in order however many times it is run. The revoke/grant
-- pair below restores the ACL that DROP removes.
drop function if exists public.fn_agent_tools(text, text);
create or replace function public.fn_agent_tools(p_agent_key text, p_kind text default null)
returns table (
  tool_id text, purpose text, kind text, impl_kind text, impl_target text,
  input_schema jsonb, timeout_seconds integer, max_attempts integer, backoff text,
  failure_behaviour text, requires_current_data boolean
)
language sql stable security definer set search_path = public as $$
  with me as (
    select a.agent_key, a.department,
           coalesce((select array_agg(i.packaged_role_id) from org_role_identity i
                      where i.agent_key = a.agent_key), '{}'::text[]) as role_ids
    from org_agents a where a.agent_key = p_agent_key and a.active
  )
  select t.tool_id, t.purpose, t.kind, t.impl_kind, t.impl_target,
         t.input_schema, t.timeout_seconds, t.max_attempts, t.backoff,
         t.failure_behaviour, t.requires_current_data
  from agent_tool t, me
  where t.active
    and t.staging_available
    and (p_kind is null or t.kind = p_kind)
    and (t.authorised_departments = '{}'::text[]
         or '*' = any(t.authorised_departments)
         or me.department = any(t.authorised_departments))
    and (t.authorised_roles = '{}'::text[]
         or '*' = any(t.authorised_roles)
         or me.role_ids && t.authorised_roles)
  order by t.kind, t.tool_id;
$$;
revoke all on function public.fn_agent_tools(text, text) from public;
grant execute on function public.fn_agent_tools(text, text) to service_role;

-- Is this agent allowed to call this specific tool? Used to REFUSE, so it must be callable
-- independently of the list above.
create or replace function public.fn_agent_tool_allowed(p_agent_key text, p_tool_id text)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.fn_agent_tools(p_agent_key) t where t.tool_id = p_tool_id);
$$;
revoke all on function public.fn_agent_tool_allowed(text, text) from public;
grant execute on function public.fn_agent_tool_allowed(text, text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 4. THE LEDGER WRITER
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_record_tool_call(
  p_correlation uuid, p_agent_key text, p_role_id text, p_tool_id text,
  p_args jsonb, p_status text, p_result_hash text, p_result_rows integer,
  p_result_bytes integer, p_error text, p_attempt integer, p_latency_ms integer)
returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into agent_tool_call (correlation_id, agent_key, role_id, tool_id, args, status,
                               result_hash, result_rows, result_bytes, error, attempt, latency_ms)
  values (p_correlation, p_agent_key, p_role_id, p_tool_id, coalesce(p_args,'{}'::jsonb), p_status,
          p_result_hash, p_result_rows, p_result_bytes, left(p_error, 500),
          coalesce(p_attempt,1), p_latency_ms)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.fn_record_tool_call(uuid,text,text,text,jsonb,text,text,integer,integer,text,integer,integer) from public;
grant execute on function public.fn_record_tool_call(uuid,text,text,text,jsonb,text,text,integer,integer,text,integer,integer) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 5. SEED — read tools only, each wrapping a routine that already exists
-- ---------------------------------------------------------------------------------------------
insert into public.agent_tool
  (tool_id, purpose, kind, impl_kind, impl_target, authorised_roles, authorised_departments,
   input_schema, timeout_seconds, failure_behaviour, requires_current_data, note)
values
  ('query_platform',
   'Read current company state: agents, ai, analytics, company, customers, documents, exec, finance, fraud, funnel, governance, knowledge, marketing, marketplace, operations, refunds, reports, strategy, suppliers.',
   'read','rpc','fn_query_platform', '{*}','{*}',
   '{"type":"object","required":["topic"],"properties":{"topic":{"type":"string","enum":["agent_ops","agents","ai","analytics","company","customers","documents","ea","exec","finance","fraud","funnel","governance","knowledge","marketing","marketplace","operations","refunds","reports","strategy","suppliers","topics"]},"args":{"type":"object"}},"additionalProperties":false}'::jsonb,
   20,'fail_closed',true,
   'The one broad live-data surface. 21 topics, already used by secretary_act.'),

  ('ops_knowledge_search',
   'Search V3 operational knowledge for the caller''s own department: policies, decision playbooks, authority records, KPI definitions.',
   'read','rpc','fn_ops_knowledge_search','{*}','{*}',
   '{"type":"object","required":["query"],"properties":{"query":{"type":"string","minLength":2},"dept":{"type":"string"},"limit":{"type":"integer","minimum":1,"maximum":20}},"additionalProperties":false}'::jsonb,
   15,'degrade_with_caveat',false,
   'Knowledge is not live data; a miss is answerable with a stated gap rather than a hard stop.'),

  ('dept_library_search',
   'Search the department reference library for technical and procedural reference material.',
   'read','rpc','fn_dept_library_search','{*}','{*}',
   '{"type":"object","required":["query"],"properties":{"query":{"type":"string","minLength":2},"dept":{"type":"string"},"limit":{"type":"integer","minimum":1,"maximum":20}},"additionalProperties":false}'::jsonb,
   15,'degrade_with_caveat',false,null),

  ('supplier_360',
   'Full current dossier for one supplier: profile, documents, licence status, capabilities, quote history.',
   'read','rpc','fn_ws_supplier_360','{*}',
   '{marketplace,supplier_success,supplier_knowledge,procurement,trust_safety,rfq_intelligence,exec}',
   '{"type":"object","required":["supplier_id"],"properties":{"supplier_id":{"type":"integer","minimum":1}},"additionalProperties":false}'::jsonb,
   15,'fail_closed',true,
   'Supplier status drives dispatch eligibility; a stale answer here is a safety issue.'),

  ('handoff_inbox',
   'Cross-department work waiting on this agent, with its acceptance criteria and deadlines.',
   'read','rpc','fn_agent_handoff_inbox','{*}','{*}',
   '{"type":"object","properties":{},"additionalProperties":false}'::jsonb,
   10,'degrade_with_caveat',true,
   'Agent key is bound server-side from the roster, never from model arguments.'),

  ('knowledge_search',
   'Hybrid semantic and keyword search over the category knowledge corpus.',
   'read','edge_function','kb_search','{*}','{*}',
   '{"type":"object","required":["query"],"properties":{"query":{"type":"string","minLength":2},"category":{"type":"string"},"k":{"type":"integer","minimum":1,"maximum":20}},"additionalProperties":false}'::jsonb,
   20,'degrade_with_caveat',false,
   'The only vector path in the runtime; everything else is lexical.')
on conflict (tool_id) do update set
  purpose = excluded.purpose, input_schema = excluded.input_schema,
  failure_behaviour = excluded.failure_behaviour, timeout_seconds = excluded.timeout_seconds,
  authorised_departments = excluded.authorised_departments, note = excluded.note;

-- ---------------------------------------------------------------------------------------------
-- 6. MONITORS — an absence check, so a regression is visible without anyone running a report
-- ---------------------------------------------------------------------------------------------
create or replace view public.v_tool_calls_never_returning as
  select t.tool_id, t.kind, t.failure_behaviour,
         count(c.id) filter (where c.created_at > now() - interval '7 days')          as calls_7d,
         count(c.id) filter (where c.status = 'ok'       and c.created_at > now() - interval '7 days') as ok_7d,
         count(c.id) filter (where c.status = 'ok_empty' and c.created_at > now() - interval '7 days') as empty_7d,
         count(c.id) filter (where c.status not in ('ok','ok_empty') and c.created_at > now() - interval '7 days') as failed_7d
  from agent_tool t left join agent_tool_call c on c.tool_id = t.tool_id
  where t.active
  group by t.tool_id, t.kind, t.failure_behaviour;
comment on view public.v_tool_calls_never_returning is
  'Per tool, per class. A tool with calls_7d > 0 and ok_7d = 0 has never actually answered - the exact shape the certification found across the whole runtime.';

commit;
