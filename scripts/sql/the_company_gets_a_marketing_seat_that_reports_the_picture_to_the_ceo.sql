-- THE COMPANY GETS A MARKETING SEAT, AND IT REPORTS THE PICTURE TO THE CEO, NOT FOR APPROVAL.   seat: ceo · 22 Sep 2026
--
-- The founder, 22 Sep 2026 (instruction 721): build the marketing agent, wired correctly, with the access it
-- needs (Postiz, Meta, everything needed). He and Claude will create posts together and ingest them to the
-- seat; it schedules them and monitors the analytics. It REPORTS TO THE CEO for the overall picture, not for
-- approval. Ad money: it collects the spend and shares it with the accountant so the accountant knows.
-- Social DMs: standard automatic replies, the seat carries the conversation; only when someone asks to speak
-- with a person is the founder notified by email, and he carries on. Wired to company knowledge.
-- Earlier rulings kept: marketing owns SEO, social, digital, business development and LinkedIn, NOT supplier
-- invitations (625); Meta and social are wired to no other seat (641).
-- Job description: docs/positions/marketing.md. Pure-probe partner: the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo_probe.sql.
--
-- MEASURED (production, read-only, 22 Sep 2026 ~13:30 Dubai):
--   * org_role: 5 active seats (accountant, ceo, customer_support, it_engineer, sales_engineer); org_agents 5;
--     org_reporting_edge 4, all to the ceo (it_engineer's edge dates from 14 Sep).
--   * function_owner_owner_ck admits ceo, customer_support, sales_engineer, accountant, it_engineer, website.
--   * seat_handoff_kind: 58 conversations, none with a marketing end. fn_seat_handoff refuses (and files an IT
--     finding for) any conversation without a row, so a seat with no rows cannot talk to anyone.
--   * app_secrets holds, set: meta_access_token, meta_ad_account_id, meta_autospend_golive, meta_campaign_filter,
--     meta_daily_budget_cap_aed, meta_sync_enabled, postiz_api_key, postiz_integrations, postiz_publish_key.
--     No key for an Instagram/Messenger webhook (app secret, verify token, page id) and none for LinkedIn.
--   * social_posts: 10 rows, all 'sent', the last on 6 Aug. ad_spend_policy month 2026-09 spent AED 0 (6 Sep).
--   * The accountant books Meta spend from the INVOICE (expense_entries -> fn_gl_sync_business) and reconciles
--     it against the reported month (fn_accountant_ad_spend_figures). Nothing records spend a seat reports.
--   * Five routines enumerate the seats by literal: fn_ceo_seat_board, fn_ceo_weekly_figures,
--     fn_it_handoff_sla_items (owner of an unanswered handoff), fn_ceo_judgement_accept and fn_channel_requester.
--
-- WHAT THIS CHANGES
--   1. The seat: function_owner_owner_ck admits 'marketing'; org_agents, org_role (tagged refusals), the edge
--      to the ceo, four standing grants, the fn.marketing credential, the owner row for its runtime, its
--      llm_seat_binding row (no model is chosen here: the founder picks the model per seat later) and a role
--      card in ops_knowledge so retrieval finds the seat's own remit.
--   2. The conversations (seat_handoff_kind), each with its handler, so nothing is one-way:
--        marketing.report     marketing -> ceo            the CEO READS it and closes it; nothing to approve
--        adspend.recorded     marketing -> accountant     the accountant records it; marketing closes it
--        adspend.booked       accountant -> marketing     the accountant's answer; marketing re-verifies
--        delivery.request     marketing -> customer_support   email/WhatsApp still go through support
--        delivery.result      customer_support -> marketing   what became of that send
--        it.finding           it_engineer -> marketing    a fault in something marketing owns
--   3. founder_mail_policy kind 'social_human_request' (allowed, owner marketing): someone on a social channel
--      asked for a person. fn_marketing_asks_the_founder_to_take_over sends it through support's door to
--      fn_notify_founder at once (level medium = email only; not the IT digest).
--   4. Tables: marketing_report (one per Dubai day) and ad_spend_reported (the accountant's record of what
--      marketing reported). RLS on, service-role-only policy, revoked from anon/authenticated.
--   5. The runtime: fn_marketing_tick (the daily report + closing the ad-spend loops), called by the marketing
--      edge function's 'duties' action, which resilience_ping calls every 30 minutes (resilience_step
--      'marketing'). The TypeScript duty list is empty and real: the publishing, analytics and social-inbox
--      builds add their duties to supabase/functions/marketing/duties.ts.
--   6. The seat lists: fn_ceo_seat_board, fn_ceo_weekly_figures and fn_it_handoff_sla_items name marketing;
--      the CEO's daily judgement request carries the latest marketing report as input.marketing.
--
-- WHAT THIS DOES NOT CHANGE
--   * No post is published, no DM is answered, no ad is bought and no Meta or Postiz call is made here.
--   * invite_enabled and supplier_outreach_golive are not read or written. Supplier invitations stay the sales
--     engineer's (instruction 625).
--   * No GL journal is written from reported spend: the invoice is the source document and is already booked
--     by the expense path; booking the reported figure too would count the same spend twice.
--   * The accountant's zero-ceiling grant accountant.meta_ads_spend (the CEO approves Meta ad spend) is
--     untouched. This file grants the marketing seat no spending authority.
--   * No ceo.directive to marketing: the CEO's plan does not direct this seat (its funnel stages are the
--     supplier and reveal stages); fn_ceo_judgement_accept's seat list is therefore unchanged.
--   * fn_ceo_founder_text_forbidden still drops any founder-brief line that says 'marketing'.
--   * No model call, no OpenRouter route, no tier decision.
--
--   node scripts/apply_sql.mjs scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql --apply --ddl

-- ── 1. THE OWNER CHECK ADMITS THE SIXTH SEAT. Widened, never dropped. ──────────────────────────────
alter table public.function_owner drop constraint if exists function_owner_owner_ck;
alter table public.function_owner add constraint function_owner_owner_ck
  check (owner = any (array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing','website']));

-- ── 2. THE AGENT (org_role.runtime_agent_key is an FK to it). No department. ───────────────────────
insert into public.org_agents (agent_key, role, kind, active, title, seniority, routing_tier, max_open_tasks, available)
values ('marketing',
        'Marketing AI -- SEO, social media, digital and business development, LinkedIn: publishes and schedules '
        'the posts the founder approved, watches the analytics, answers the company''s social inbox from company '
        'knowledge, collects ad spend for the accountant and reports the overall picture to the CEO.',
        'brain', true, 'Marketing', 'specialist', 'analyst_controller', 20, true)
on conflict (agent_key) do update
  set role = excluded.role, active = excluded.active, title = excluded.title, seniority = excluded.seniority,
      routing_tier = excluded.routing_tier, max_open_tasks = excluded.max_open_tasks, available = excluded.available;

-- ── 3. THE ROLE. Every refusal is tagged with the class it refuses, as the IT engineer's are. ────────
insert into public.org_role (role_id, display_name, runtime_mode, runtime_agent_key, authority_level,
                             responsibilities, activation_conditions, owned_decisions, forbidden_decisions,
                             handoff_targets, escalation_targets)
values ('marketing', 'Marketing', 'event_driven_operator', 'marketing', 'execute_low',
  'Own how buyers and the market find QuotesDone: SEO, social media, digital, business development and LinkedIn. '
  'Schedule and publish the posts the founder created and approved with Claude, on the company''s own channels '
  '(Postiz, Meta); measure what each channel returns; answer the company''s social inbox with standard replies '
  'grounded in company knowledge and carry the conversation; hand a conversation to the founder the moment '
  'someone asks for a person; collect the ad spend every platform reports and hand it to the accountant; report '
  'the overall picture to the CEO every day. A figure it cannot measure is reported as not measured, never as zero.',
  'An approved post is due; a platform''s analytics can be read; a DM or comment arrives on a company account; '
  'someone asks to speak with a person; a platform reports spend; the daily reporting window opens.',
  array['when an approved post goes out, inside the schedule the founder agreed',
        'the standard reply to a social message, from company knowledge',
        'when a social conversation needs the founder (someone asked for a person)',
        'what the marketing report says, and which figures are not measured yet'],
  array['[supplier_invitations] INVITING SUPPLIERS OR RUNNING THE SUPPLIER OUTREACH CAMPAIGN -- the sales engineer''s (founder instruction 625); the campaign switches are the founder''s.',
        '[publish_unapproved] PUBLISHING A POST THE FOUNDER DID NOT APPROVE -- the route is the founder: he and Claude create the posts and ingest them to this seat.',
        '[ad_spend] RAISING, STARTING OR MOVING AD SPEND -- no grant: the route is the CEO (accountant.meta_ads_spend) and the founder''s go-live switch.',
        '[customer_email] EMAILING OR WHATSAPPING A CUSTOMER OR SUPPLIER -- customer_support is the only sender; the sales engineer addresses customers and suppliers.',
        '[books] BOOKING SPEND IN THE LEDGER -- the accountant''s: this seat reports spend through adspend.recorded.',
        '[price_or_policy] STATING A FEE, A DATE OR A POLICY NOT IN THE COMPANY BLOCK -- the route is company knowledge, or the founder when it is not there.'],
  array['ceo','accountant','customer_support'],
  array['ceo'])
on conflict (role_id) do update
  set display_name = excluded.display_name, runtime_mode = excluded.runtime_mode,
      runtime_agent_key = excluded.runtime_agent_key, authority_level = excluded.authority_level,
      responsibilities = excluded.responsibilities, activation_conditions = excluded.activation_conditions,
      owned_decisions = excluded.owned_decisions, forbidden_decisions = excluded.forbidden_decisions,
      handoff_targets = excluded.handoff_targets, escalation_targets = excluded.escalation_targets;

-- ── 4. THE EDGE. "It reports to the CEO for the overall picture", in his words. ─────────────────────
insert into public.org_reporting_edge (child_role_id, parent_role_id, established_by, reason)
values ('marketing', 'ceo', 'founder',
        'Founder ruling 22 Sep 2026 (instruction 721): the marketing seat reports to the CEO for the overall picture, '
        'NOT for approval. Sixth seat. No marketing department, no director.')
on conflict (child_role_id) do update set parent_role_id = excluded.parent_role_id, reason = excluded.reason;

-- ── 5. THE STANDING GRANTS. What the founder described, and no spending authority. ──────────────────
insert into public.ceo_standing_grant
  (grant_key, grantee_role_id, action_class, scope_note, limit_note, max_amount_aed, issued_by, active)
values
  ('marketing.publishing', 'marketing', 'publishing',
   'Schedule and publish posts on the company''s own social and web channels (Postiz, Meta, LinkedIn, the blog).',
   'Only posts the founder created or approved and ingested to this seat. Never a post it wrote alone.', null, 'ceo', true),
  ('marketing.analytics', 'marketing', 'analytics',
   'Read each channel''s analytics and the ad platforms'' reports, and keep the figures.',
   'Read-only on the platforms. A figure it could not read is recorded as not measured.', null, 'ceo', true),
  ('marketing.social_conversation', 'marketing', 'social_conversation',
   'Answer DMs and comments on the company''s social accounts with standard replies from company knowledge, and carry the conversation.',
   'Hands the conversation to the founder the moment someone asks for a person (fn_marketing_asks_the_founder_to_take_over) and stops replying on that thread.', null, 'ceo', true),
  ('marketing.ad_spend_reporting', 'marketing', 'ad_spend_reporting',
   'Collect the spend every ad platform reports and hand it to the accountant (adspend.recorded).',
   'Reporting only: it grants no authority to start, raise or move spend.', null, 'ceo', true)
on conflict (grant_key) do update
  set scope_note = excluded.scope_note, limit_note = excluded.limit_note,
      max_amount_aed = excluded.max_amount_aed, active = excluded.active;

-- ── 6. THE SCOPED CREDENTIAL. Generated here; the value never leaves the database. ─────────────────
do $mint$
declare v_secret text;
begin
  if exists (select 1 from public.internal_credential where context = 'fn.marketing') then return; end if;
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
  values ('fn.marketing', 'The Marketing seat -- publishing, analytics, the social inbox, ad-spend reporting',
          public.fn_internal_credential_hash(v_secret), array['marketing'], false, true);
  insert into public.app_secrets (key, value) values ('cred_fn_marketing', v_secret)
  on conflict (key) do update set value = excluded.value;
end
$mint$;

-- ── 7. THE OWNER ROW AND THE MODEL-BINDING ROW, before the deploy. ─────────────────────────────────
insert into public.function_owner (function_slug, owner, note)
values ('marketing', 'marketing',
        'The Marketing seat''s own runtime (founder instruction 721, 22 Sep 2026). The only code allowed to name the '
        'Meta and Postiz credentials (rule 641; scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs). '
        'Its duty list is supabase/functions/marketing/duties.ts; resilience_ping calls it every 30 minutes.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

insert into public.llm_seat_binding (fn, seat, note)
values ('marketing', 'marketing',
        'The marketing seat''s own runtime. Deterministic first; the model per seat is the founder''s to set.')
on conflict (fn) do update set seat = excluded.seat, note = excluded.note;

-- ── 8. THE ROLE CARD IN COMPANY KNOWLEDGE. Embedded by the backfill (embedding_status 'pending'). ───
insert into public.ops_knowledge (record_id, scope_type, scope_key, module, record_type, title, content,
                                  implementation_status, validation_status, authority_tier, risk_level, version,
                                  layer, role_key, source_type, confidentiality, runtime_eligible, deterministic,
                                  supersession_state, keywords)
values ('seat:marketing:role_card', 'role', 'marketing', 'role', 'md',
  'Marketing seat: role card (founder instruction 721, 22 September 2026)',
  'The marketing seat owns how buyers and the market find QuotesDone: SEO, social media, digital marketing, business '
  'development and LinkedIn. It does not invite suppliers: supplier invitations are the sales engineer''s. It publishes '
  'and schedules only posts the founder created or approved, through Postiz and Meta, and measures what each channel '
  'returns. It answers direct messages and comments on the company''s social accounts with standard replies grounded '
  'in company knowledge and carries the conversation; when someone asks to speak with a person, the founder is '
  'emailed at once and he carries on the conversation. It collects the ad spend each platform reports and hands it to '
  'the accountant, who records it; the ledger entry comes from the platform''s invoice. It reports the overall '
  'picture to the CEO every day; the CEO reads the report and does not approve it. Email and WhatsApp go through '
  'customer support; replies on the company''s own social channels are sent by this seat.',
  'implemented', 'author_verified', 'advisory', 'low', '2026.09.22', 'role_specific', 'marketing',
  'founder_instruction', 'internal', true, true, 'current',
  array['marketing','seo','social media','instagram','linkedin','meta','postiz','ad spend','business development'])
on conflict (record_id) do update set content = excluded.content, title = excluded.title, version = excluded.version;

-- Rule 641's standing decision said "until the marketing seat exists". It exists now.
update public.company_policy_decision
   set decision_text = 'Founder rules 641 and 721: Meta, ads and social are the marketing seat''s alone and wired to no '
                    || 'other seat. The held credentials (meta_access_token, meta_ad_account_id, postiz_api_key, '
                    || 'postiz_publish_key, postiz_integrations) are read only by supabase/functions/marketing and by '
                    || 'routines named fn_marketing_*, fn_ads_* or fn_ad_* '
                    || '(scripts/checks/meta_and_social_are_held_for_the_marketing_seat.test.mjs).'
 where decision_key = 'meta_and_social_held_for_marketing';

-- ── 9. THE TWO TABLES ───────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_report (
  report_date    date primary key,                       -- the Dubai day the report was filed
  window_from    timestamptz not null,
  window_to      timestamptz not null check (window_to > window_from),
  figures        jsonb not null check (jsonb_typeof(figures) = 'object'),
  no_data_yet    boolean not null,                       -- true when no measured figure is above zero
  handoff_id     bigint,                                 -- the marketing.report handoff to the ceo
  read_by_ceo_at timestamptz,                            -- the CEO's read receipt; nothing is approved
  created_at     timestamptz not null default now()
);
alter table public.marketing_report enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'marketing_report') then
    create policy marketing_report_service_role_only on public.marketing_report as permissive for all to public using (false) with check (false);
  end if;
end $$;
revoke all on public.marketing_report from anon, authenticated;
comment on table public.marketing_report is
  'The marketing seat''s daily report to the CEO (founder instruction 721): the overall picture, read not approved. Written by fn_marketing_report_tick.';

create table if not exists public.ad_spend_reported (
  source_ref   text primary key check (btrim(source_ref) <> ''),  -- the platform's own reference: one row per platform day (or campaign day)
  platform     text not null check (platform ~ '^[a-z][a-z0-9_]*$'),
  spend_date   date not null,
  currency     text not null check (currency ~ '^[A-Z]{3}$'),
  amount       numeric(14,2) not null check (amount >= 0),
  amount_aed   numeric(14,2),                                     -- null when gl_settings has no rate for the currency
  campaign_ref text,
  handoff_id   bigint not null,                                   -- the adspend.recorded handoff it came in on
  revisions    int not null default 1 check (revisions >= 1),
  recorded_at  timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table public.ad_spend_reported enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ad_spend_reported') then
    create policy ad_spend_reported_service_role_only on public.ad_spend_reported as permissive for all to public using (false) with check (false);
  end if;
end $$;
revoke all on public.ad_spend_reported from anon, authenticated;
comment on table public.ad_spend_reported is
  'The accountant''s record of the ad spend the marketing seat reported (adspend.recorded). Not a ledger: the GL entry comes from the platform''s invoice (expense_entries -> fn_gl_sync_business). Test money is never recorded.';

-- ── 10. THE FOUNDER-MAIL KIND ─────────────────────────────────────────────────────────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('social_human_request', true,
        'Founder instruction 721, 22 Sep 2026: on social DMs the marketing seat replies and carries the conversation; '
        'only when someone asks to speak with a person is the founder notified by email, and he carries on. Sent at once '
        '(not the IT digest), email only (level medium), at most one per conversation per day.',
        'marketing')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason,
                                 owner_role = excluded.owner_role, updated_at = now();

-- ── 11. THE CONVERSATIONS. The TypeScript half is supabase/functions/_shared/payment_handoffs.ts; ────
-- scripts/checks/payments_are_the_accountant.test.mjs fails if the two lists differ, and fails a row whose
-- handler or producer does not exist.
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('marketing.report', 'marketing', 'ceo',
   'The marketing seat''s daily report: the overall picture, for the CEO to read. Informational: the CEO reads it and closes it; nothing is approved.',
   'fn_ceo_reads_marketing_report', interval '1 day', false,
   'scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql'),
  ('adspend.recorded', 'marketing', 'accountant',
   'An ad platform reported spend for a day: the accountant records it on its ad-spend record and answers with adspend.booked. Marketing re-verifies and closes it.',
   'fn_accountant_keeps_reported_ad_spend', interval '1 day', true,
   'scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql'),
  ('adspend.booked', 'accountant', 'marketing',
   'The accountant''s answer to adspend.recorded: what it recorded, the month so far, and that the ledger entry comes from the invoice.',
   'fn_marketing_notes_ad_spend_booked', interval '1 day', false,
   'scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql'),
  ('delivery.request', 'marketing', 'customer_support',
   'Deliver this notice by email or WhatsApp: today only to the founder (a social conversation that asked for a person).',
   'fn_customer_support_acts_on_handoff', interval '1 hour', false,
   'scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql'),
  ('delivery.result', 'customer_support', 'marketing',
   'What became of the send the marketing seat asked for: delivered with the provider''s id, or why not.',
   'fn_delivery_result_acts', null, false,
   'scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql'),
  ('it.finding', 'it_engineer', 'marketing',
   'The IT engineer found a fault in something the marketing seat owns: apply your remedy or say you have none. The IT engineer re-verifies and closes it.',
   'fn_seat_answers_it_finding', interval '4 hours', true,
   'scripts/sql/the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql')
on conflict (type, from_seat, to_seat) do update
  set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within,
      originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

-- ── 12. THE SEAT READS THE COMPANY KNOWLEDGE ────────────────────────────────────────────────────────
-- Founder ruling, 9 Sep 2026: "the company knowledge is literally connected to every seat automatically".
-- The company block is pinned on every return, refusals included. Retrieval is ops_knowledge (the growth and
-- marketplace playbooks and this seat's role card) under the same admission rule as fn_it_engineer_assist: a row
-- with a vector must clear the cosine floor AND corroborate literally; a row reached only lexically must clear
-- the stricter lexical bar. Without an embedding the vector route is simply not taken.
create or replace function public.fn_marketing_assist(p_text text, p_embedding vector default null,
  p_min_similarity numeric default 0.83, p_min_rank numeric default 0.05, p_k integer default 5, p_min_overlap numeric default 0.60)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_k int := greatest(1, least(coalesce(p_k, 5), 20)); v_wide int := greatest(v_k * 4, 20);
  c_lex_only numeric := greatest(0.20, coalesce(p_min_rank, 0));
  v_tq tsquery; v_lex text[]; v_nlex int; v_need int; v_records jsonb; v_cited text[];
begin
  if coalesce(btrim(p_text), '') = '' then
    return jsonb_build_object('company', public.fn_company_context(), 'ok', false, 'answered', false, 'refusal', 'empty_query');
  end if;
  v_tq := websearch_to_tsquery('english', p_text);
  select array_agg(distinct u.lexeme) into v_lex from unnest(to_tsvector('english', p_text)) u;
  v_nlex := coalesce(cardinality(v_lex), 0);
  v_need := case when v_nlex = 0 then 2147483647
                 else greatest(least(2, v_nlex), ceil(coalesce(p_min_overlap, 0.60) * v_nlex)::int) end;

  with cand as (
    select o.record_id, o.title, left(o.content, 4000) content, o.module, o.layer,
           (1 - (o.embedding_gte <=> p_embedding))::numeric sim,
           coalesce(ts_rank(o.tsv, v_tq), 0)::numeric * (case when o.tsv @@ v_tq then 1 else 0 end) rnk,
           (select count(*) from unnest(o.tsv) u where u.lexeme = any (v_lex))::int hits, true has_vec
      from public.ops_knowledge o
     where p_embedding is not null and o.embedding_gte is not null
       and coalesce(o.supersession_state, 'current') = 'current'
     order by o.embedding_gte <=> p_embedding limit v_wide
  ), lex as (
    select o.record_id, o.title, left(o.content, 4000) content, o.module, o.layer,
           null::numeric sim, ts_rank(o.tsv, v_tq)::numeric rnk, 0 hits, false has_vec
      from public.ops_knowledge o
     where o.tsv @@ v_tq and coalesce(o.supersession_state, 'current') = 'current'
       and not exists (select 1 from cand c where c.record_id = o.record_id)
     order by ts_rank(o.tsv, v_tq) desc limit v_wide
  ), judged as (
    select x.*, case when x.has_vec then x.sim >= p_min_similarity and (x.rnk >= p_min_rank or x.hits >= v_need)
                     else x.rnk >= c_lex_only end ok
      from (select * from cand union all select * from lex) x
  ), top as (
    select j.* from judged j where j.ok order by j.has_vec desc, j.sim desc nulls last, j.rnk desc limit v_k
  )
  select coalesce(jsonb_agg(jsonb_build_object('corpus', 'ops_knowledge', 'record_id', t.record_id, 'title', t.title,
                                               'provenance', coalesce(t.module, '') || coalesce(' · ' || t.layer, ''),
                                               'similarity', round(t.sim, 4), 'lexical_rank', round(t.rnk, 4),
                                               'route', case when t.has_vec then 'vector+lexical' else 'lexical_only' end,
                                               'content', t.content)), '[]'::jsonb),
         coalesce(array_agg('ops_knowledge:' || t.record_id), '{}')
    into v_records, v_cited from top t;

  return jsonb_build_object('company', public.fn_company_context(), 'ok', true, 'answered', cardinality(v_cited) > 0,
    'records', v_records, 'cited', v_cited, 'corpora', jsonb_build_array('ops_knowledge'),
    'floor', jsonb_build_object('min_similarity', p_min_similarity, 'min_rank', p_min_rank, 'lexical_only', c_lex_only,
                                'lexeme_overlap_needed', v_need, 'vector_route', p_embedding is not null),
    'refusal', case when cardinality(v_cited) = 0 then 'no_sourced_answer' end,
    'handoff', case when cardinality(v_cited) = 0 then
      'No sourced answer in company knowledge. Reply with the standard holding line and do not state a fee, date or policy; '
      || 'if the person asks for someone, hand the conversation to the founder (fn_marketing_asks_the_founder_to_take_over).' end);
end $fn$;
revoke execute on function public.fn_marketing_assist(text, vector, numeric, numeric, integer, numeric) from public, anon, authenticated;

-- ── 13. THE DAILY REPORT TO THE CEO ───────────────────────────────────────────────────────────────
-- Every figure is read from a row that exists. What no instrument measures yet is listed by name under
-- 'not_measured', so a zero never stands in for "nobody looked". The publishing, analytics and inbox builds
-- replace this routine to add their own figures; the shape (headline, measured, not_measured) stays.
create or replace function public.fn_marketing_report_figures(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_posts int; v_posts_ever int; v_spend jsonb; v_spend_aed numeric; v_unconv int; v_asked int; v_inq numeric; v_head text;
begin
  select count(*) filter (where coalesce(schedule_at, created_at) >= p_from and coalesce(schedule_at, created_at) < p_to),
         count(*)
    into v_posts, v_posts_ever from public.social_posts where status = 'sent';
  select coalesce(jsonb_object_agg(platform, aed), '{}'::jsonb), coalesce(sum(aed), 0), coalesce(sum(unconv), 0)
    into v_spend, v_spend_aed, v_unconv
    from (select platform, sum(amount_aed) aed, count(*) filter (where amount_aed is null) unconv
            from public.ad_spend_reported where spend_date >= (p_from at time zone 'Asia/Dubai')::date
                                           and spend_date < (p_to at time zone 'Asia/Dubai')::date
           group by platform) s;
  select count(*) into v_asked from public.notifications
   where kind = 'social_human_request' and created_at >= p_from and created_at < p_to;
  v_inq := public.fn_ceo_plan_measure('inquiries_posted', p_from, p_to)::numeric;
  v_head := format('%s post(s) published, AED %s ad spend reported, %s conversation(s) handed to the founder, %s customer request(s) posted.',
                   v_posts, v_spend_aed, v_asked, coalesce(v_inq::text, 'unmeasured'));
  return jsonb_build_object(
    'headline', v_head,
    'measured', jsonb_build_object(
      'posts_published', v_posts, 'posts_published_ever', v_posts_ever,
      'ad_spend_reported_aed', v_spend_aed, 'ad_spend_by_platform_aed', v_spend, 'ad_spend_rows_unconverted', v_unconv,
      'conversations_handed_to_founder', v_asked, 'customer_requests_posted', v_inq),
    'not_measured', jsonb_build_array(
      'followers, reach and engagement per channel: no analytics reader is built yet',
      'social conversations answered: no social inbox record is built yet',
      'search rankings and organic traffic: no SEO reader is built yet',
      'LinkedIn: no LinkedIn credential is on file'),
    'basis', 'Posts: social_posts with status sent, by schedule_at (else created_at). Spend: ad_spend_reported by spend_date (Asia/Dubai), in AED at gl_settings usd_to_aed. Handed to the founder: notifications of kind social_human_request. Customer requests: fn_ceo_plan_measure(inquiries_posted), demo excluded. Window: the 24 hours before the report.');
end $fn$;
revoke execute on function public.fn_marketing_report_figures(timestamptz, timestamptz) from public, anon, authenticated;

-- Once per Dubai day from 07:00 (after the CEO's 06:00 plan, so the CEO reads it the same day).
create or replace function public.fn_marketing_report_tick(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_local timestamp := p_at at time zone 'Asia/Dubai'; f jsonb; v_none boolean; v_hid bigint;
begin
  if exists (select 1 from public.marketing_report where report_date = v_local::date) then
    return jsonb_build_object('ok', true, 'reported', false, 'reason', 'today''s report exists');
  end if;
  if v_local::time < time '07:00' then
    return jsonb_build_object('ok', true, 'reported', false, 'reason', 'before 07:00 Dubai');
  end if;
  f := public.fn_marketing_report_figures(p_at - interval '1 day', p_at);
  v_none := coalesce((f->'measured'->>'posts_published')::numeric, 0) = 0
        and coalesce((f->'measured'->>'ad_spend_reported_aed')::numeric, 0) = 0
        and coalesce((f->'measured'->>'conversations_handed_to_founder')::numeric, 0) = 0
        and coalesce((f->'measured'->>'customer_requests_posted')::numeric, 0) = 0;
  if v_none then
    f := f || jsonb_build_object('headline', 'No data yet: nothing was published, spent or handed over in the last 24 hours, and no customer request was posted. ' || (f->>'headline'));
  end if;
  insert into public.marketing_report (report_date, window_from, window_to, figures, no_data_yet)
  values (v_local::date, p_at - interval '1 day', p_at, f, v_none);
  v_hid := public.fn_seat_handoff('marketing', 'ceo', 'marketing.report', 'marketing_report', v_local::date::text,
                                  jsonb_build_object('report_date', v_local::date, 'headline', f->>'headline', 'no_data_yet', v_none));
  update public.marketing_report set handoff_id = v_hid where report_date = v_local::date;
  return jsonb_build_object('ok', true, 'reported', true, 'report_date', v_local::date, 'handoff_id', v_hid, 'no_data_yet', v_none);
end $fn$;
revoke execute on function public.fn_marketing_report_tick(timestamptz) from public, anon, authenticated;

-- The CEO's handler. It READS: a read receipt on the report and the headline in its reply. Nothing is
-- approved and nothing is decided, so the handoff closes on the read (originator_closes false).
create or replace function public.fn_ceo_reads_marketing_report(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; m public.marketing_report;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'marketing.report' then
    raise exception 'fn_ceo_reads_marketing_report: % is not a marketing.report handoff', p_id;
  end if;
  update public.marketing_report set read_by_ceo_at = coalesce(read_by_ceo_at, now())
   where report_date = (a.detail->>'subject_id')::date returning * into m;
  if m.report_date is null then
    raise exception 'marketing.report % names report %, which does not exist', p_id, a.detail->>'subject_id';
  end if;
  return jsonb_build_object('read', true, 'read_at', m.read_by_ceo_at, 'report_date', m.report_date,
                            'headline', m.figures->>'headline', 'no_data_yet', m.no_data_yet,
                            'note', 'Read by the CEO for the overall picture. Informational: nothing was approved or decided.');
end $fn$;
revoke execute on function public.fn_ceo_reads_marketing_report(bigint) from public, anon, authenticated;

-- ── 14. AD SPEND: MARKETING REPORTS IT, THE ACCOUNTANT RECORDS IT, MARKETING CLOSES THE LOOP ─────────
-- THE ONE DOOR the ad-spend build calls, once per platform day (or campaign day). The same source_ref with a
-- new amount is a revision: it opens a new conversation and the accountant's row is updated, never duplicated.
-- Test money never reaches the accountant's record: p_test, or a ZZ DEMO reference.
-- THE TWO CONSUMERS carry the names the publishing/ad-spend build (PR #834) uses, so its file, applied after
-- this one, replaces them by MANIFEST order rather than adding a second pair. Whatever replaces them keeps the
-- contract fn_marketing_closes_ad_spend_loops reads: adspend.booked carries detail.recorded_handoff (the id of
-- the adspend.recorded it answers), and marketing's handler returns evidence.verified (boolean).
-- fn_seat_handoff_act resolves the handler by name at run time, so neither side needs the other at compile time.
create or replace function public.fn_marketing_records_ad_spend(p_platform text, p_spend_date date, p_currency text,
  p_amount numeric, p_source_ref text, p_campaign_ref text default null, p_test boolean default false)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_test boolean;
begin
  if coalesce(p_platform, '') !~ '^[a-z][a-z0-9_]*$' then raise exception 'platform must be a lowercase key such as meta or linkedin, got %', p_platform; end if;
  if p_spend_date is null then raise exception 'spend_date is required'; end if;
  if coalesce(upper(p_currency), '') !~ '^[A-Z]{3}$' then raise exception 'currency must be an ISO code, got %', p_currency; end if;
  if p_amount is null or p_amount < 0 then raise exception 'amount must be >= 0, got %', p_amount; end if;
  if coalesce(btrim(p_source_ref), '') = '' then raise exception 'source_ref (the platform''s own reference for this spend) is required'; end if;
  v_test := coalesce(p_test, false) or p_source_ref ~* 'zz[ _-]?demo' or coalesce(p_campaign_ref, '') ~* 'zz[ _-]?demo';
  return public.fn_seat_handoff('marketing', 'accountant', 'adspend.recorded', 'ad_spend_reported',
    p_source_ref || '@' || round(p_amount, 2)::text,
    jsonb_build_object('platform', p_platform, 'spend_date', p_spend_date, 'currency', upper(p_currency),
                       'amount', round(p_amount, 2), 'source_ref', p_source_ref, 'campaign_ref', p_campaign_ref,
                       'test', v_test, 'demo', v_test));
end $fn$;
revoke execute on function public.fn_marketing_records_ad_spend(text, date, text, numeric, text, text, boolean) from public, anon, authenticated;

-- The accountant's handler: record it, then answer with adspend.booked. It waits for marketing to close it.
create or replace function public.fn_accountant_keeps_reported_ad_spend(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; d jsonb; v_test boolean; v_fx numeric; v_aed numeric; v_recorded boolean := false;
        v_month date; v_pos jsonb; v_inv jsonb; v_bid bigint;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'adspend.recorded' then
    raise exception 'fn_accountant_keeps_reported_ad_spend: % is not an adspend.recorded handoff', p_id;
  end if;
  d := a.detail;
  v_test := coalesce((d->>'test')::boolean, false) or coalesce(d->>'source_ref', '') ~* 'zz[ _-]?demo';
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);
  v_aed := case d->>'currency' when 'AED' then (d->>'amount')::numeric
                               when 'USD' then round((d->>'amount')::numeric * v_fx, 2) end;
  v_month := date_trunc('month', (d->>'spend_date')::date)::date;

  if not v_test then
    insert into public.ad_spend_reported (source_ref, platform, spend_date, currency, amount, amount_aed, campaign_ref, handoff_id)
    values (d->>'source_ref', d->>'platform', (d->>'spend_date')::date, d->>'currency', (d->>'amount')::numeric, v_aed,
            nullif(d->>'campaign_ref', ''), p_id)
    on conflict (source_ref) do update
      set amount = excluded.amount, amount_aed = excluded.amount_aed, currency = excluded.currency,
          spend_date = excluded.spend_date, campaign_ref = excluded.campaign_ref, handoff_id = excluded.handoff_id,
          revisions = ad_spend_reported.revisions + 1, updated_at = now();
    v_recorded := true;
  end if;

  select jsonb_build_object('platform', d->>'platform', 'month', to_char(v_month, 'YYYY-MM'),
                            'reported_aed', coalesce(sum(amount_aed), 0), 'rows', count(*),
                            'rows_unconverted', count(*) filter (where amount_aed is null))
    into v_pos from public.ad_spend_reported
   where platform = d->>'platform' and spend_date >= v_month and spend_date < (v_month + interval '1 month')::date;
  if d->>'platform' = 'meta' then
    begin
      v_inv := public.fn_accountant_ad_spend_figures(v_month);
      v_pos := v_pos || jsonb_build_object('invoiced_aed', v_inv->'invoiced_aed', 'meta_invoices', v_inv->'meta_invoices');
    exception when others then
      v_pos := v_pos || jsonb_build_object('invoiced_aed', null, 'invoiced_error', left(sqlerrm, 200));
    end;
  end if;

  v_bid := public.fn_seat_handoff('accountant', 'marketing', 'adspend.booked', 'ad_spend_reported', (d->>'source_ref') || '@' || (d->>'amount'),
    jsonb_build_object('recorded_handoff', p_id, 'source_ref', d->>'source_ref', 'amount', d->'amount', 'currency', d->>'currency',
                       'amount_aed', v_aed, 'recorded', v_recorded, 'test', v_test, 'demo', v_test, 'month_position', v_pos,
                       'books', case when v_test then 'Test money: not recorded and never booked.'
                                     else 'Recorded on the accountant''s ad-spend record. The ledger entry is made from the platform''s invoice when it reaches the expenses mailbox (fn_gl_sync_business); booking the reported figure as well would count the same spend twice.' end));
  return jsonb_build_object('waiting', 'marketing re-verification of adspend.booked ' || v_bid, 'recorded', v_recorded,
                            'test', v_test, 'amount_aed', v_aed, 'booked_handoff', v_bid, 'month_position', v_pos);
end $fn$;
revoke execute on function public.fn_accountant_keeps_reported_ad_spend(bigint) from public, anon, authenticated;

-- Marketing's handler for the answer: re-verify it against the accountant's record, row by row.
create or replace function public.fn_marketing_notes_ad_spend_booked(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; d jsonb; r public.ad_spend_reported; v_ok boolean; v_why text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'adspend.booked' then
    raise exception 'fn_marketing_notes_ad_spend_booked: % is not an adspend.booked handoff', p_id;
  end if;
  d := a.detail;
  select * into r from public.ad_spend_reported where source_ref = d->>'source_ref';
  if coalesce((d->>'recorded')::boolean, false) then
    v_ok := r.source_ref is not null and r.amount = (d->>'amount')::numeric;
    v_why := case when r.source_ref is null then 'the accountant said recorded and no row exists'
                  when not v_ok then 'the accountant''s row says ' || r.amount || ', marketing reported ' || (d->>'amount') end;
  else
    v_ok := coalesce((d->>'test')::boolean, false);
    v_why := case when not v_ok then 'the accountant did not record real spend' end;
  end if;
  return jsonb_build_object('verified', v_ok, 'reason', v_why, 'recorded_handoff', d->'recorded_handoff');
end $fn$;
revoke execute on function public.fn_marketing_notes_ad_spend_booked(bigint) from public, anon, authenticated;

-- The originator closes. A verified answer closes adspend.recorded; an unverified one stays open, and
-- fn_it_handoff_sla_items files it to the CEO once it is past its window ("unclosed").
create or replace function public.fn_marketing_closes_ad_spend_loops()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare h public.agent_actions; b public.agent_actions; n_closed int := 0; n_mismatch int := 0; n_wait int := 0;
begin
  for h in select * from public.agent_actions
            where kind = 'handoff' and agent = 'accountant' and detail->>'type' = 'adspend.recorded'
              and detail->>'from' = 'marketing' and status = 'pending' and detail ? 'replied_at'
            order by id limit 200 loop
    select * into b from public.agent_actions
     where kind = 'handoff' and agent = 'marketing' and detail->>'type' = 'adspend.booked'
       and (detail->>'recorded_handoff')::bigint = h.id and status = 'done'
     order by id desc limit 1;
    if b.id is null then
      n_wait := n_wait + 1;
    elsif coalesce((b.evidence->>'verified')::boolean, false) then
      perform set_config('qd.handoff_closer', 'marketing', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'marketing', 'verified_at', now(), 'verdict', 'recorded as reported (adspend.booked ' || b.id || ')'));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    else
      n_mismatch := n_mismatch + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'closed', n_closed, 'mismatch', n_mismatch, 'waiting', n_wait);
end $fn$;
revoke execute on function public.fn_marketing_closes_ad_spend_loops() from public, anon, authenticated;

-- ── 15. SOMEONE ON SOCIAL ASKED FOR A PERSON: THE FOUNDER IS EMAILED, AT ONCE ────────────────────────
-- The social-inbox build calls this and then marks its own conversation handed to a person, and stops
-- replying on it. The email goes through customer_support's door (delivery.request, recipient founder), which
-- calls fn_notify_founder under founder_mail_policy 'social_human_request'. One per conversation per Dubai day.
-- A ZZ DEMO conversation is refused before anything is queued: a probe cannot reach the founder through here.
create or replace function public.fn_marketing_asks_the_founder_to_take_over(p_platform text, p_thread_ref text,
  p_handle text, p_last_message text, p_summary text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_subject text; v_id bigint; a public.agent_actions;
begin
  if coalesce(p_platform, '') !~ '^[a-z][a-z0-9_]*$' or coalesce(btrim(p_thread_ref), '') = '' then
    raise exception 'a handover names its platform (lowercase key) and the platform''s thread reference';
  end if;
  if concat_ws(' ', p_thread_ref, p_handle, p_last_message) ~* 'zz[ _-]?demo' then
    return jsonb_build_object('asked', false, 'reason', 'a ZZ DEMO conversation never reaches the founder');
  end if;
  v_subject := p_platform || ':' || p_thread_ref || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  v_id := public.fn_seat_handoff('marketing', 'customer_support', 'delivery.request', 'social_conversation', v_subject,
    jsonb_build_object('recipient_role', 'founder', 'kind', 'social_human_request', 'level', 'medium',
      'dedupe_key', 'social_human_request:' || v_subject,
      'event', 'Someone on ' || initcap(p_platform) || ' asked to speak with a person',
      'detail', coalesce(nullif(btrim(p_handle), ''), 'A person') || ' asked to speak with a person on ' || initcap(p_platform)
                || ' (conversation ' || p_thread_ref || ').' || E'\n\nTheir last message: ' || left(coalesce(p_last_message, ''), 1000)
                || coalesce(E'\n\nThe conversation so far: ' || left(nullif(btrim(p_summary), ''), 1500), '')
                || E'\n\nThe automatic replies on this conversation have stopped. Please reply to them directly on '
                || initcap(p_platform) || '.',
      'platform', p_platform, 'thread_ref', p_thread_ref));
  select * into a from public.agent_actions where id = v_id;
  return jsonb_build_object('asked', a.status <> 'failed', 'handoff_id', v_id, 'status', a.status,
                            'notification_id', a.evidence->'notification_id', 'error', a.detail->>'error');
end $fn$;
revoke execute on function public.fn_marketing_asks_the_founder_to_take_over(text, text, text, text, text) from public, anon, authenticated;

-- ── 16. THE SEAT'S TICK. The edge function's 'duties' action calls it after its own duty list. ────────
create or replace function public.fn_marketing_tick(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_rep jsonb; v_ads jsonb;
begin
  begin v_rep := public.fn_marketing_report_tick(p_at);
  exception when others then v_rep := jsonb_build_object('ok', false, 'error', left(sqlerrm, 300)); end;
  begin v_ads := public.fn_marketing_closes_ad_spend_loops();
  exception when others then v_ads := jsonb_build_object('ok', false, 'error', left(sqlerrm, 300)); end;
  return jsonb_build_object('ok', coalesce((v_rep->>'ok')::boolean, false) and coalesce((v_ads->>'ok')::boolean, false),
                            'report', v_rep, 'ad_spend_loops', v_ads);
end $fn$;
revoke execute on function public.fn_marketing_tick(timestamptz) from public, anon, authenticated;

-- On the heartbeat: resilience_ping step 'marketing' (supabase/functions/resilience_ping/index.ts).
insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('marketing', interval '30 minutes', 3000, 'plan', 0,
   'The marketing seat''s duties (supabase/functions/marketing/duties.ts) and fn_marketing_tick: the daily report to the CEO and the ad-spend loops')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place,
                                rank = excluded.rank, note = excluded.note;

-- ── 17. THE CEO READS THE MARKETING PICTURE IN ITS DAILY JUDGEMENT ────────────────────────────────
-- input.marketing is the latest report. It is information for the plan, not a seat the plan directs.
create or replace function public.fn_ceo_judgement_contract()
returns jsonb language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'version', 'ceo-judgement-v1',
    'system', 'You are the chief executive of QuotesDone, a UAE construction-procurement marketplace. Customers post requests; verified suppliers quote; the customer sees a free comparison of the best three technical quotes plus every other quote, and pays a 3% reveal fee (plus card processing) to reveal the supplier they choose. Suppliers pay no commission. The company goal is AED 1,000,000 of reveal-fee revenue by 31 August 2027. You direct four seats: sales_engineer, customer_support, accountant, it_engineer. The marketing seat reports its overall picture to you in input.marketing: read it as information, it is not a seat you direct here. Decide ONLY from the numbers in the input; never invent one. You may not move money, change a supplier or customer record, message a customer, a supplier or the founder, or touch any founder switch. The supplier invitation campaign (its go, its switches, its daily volume and ramp), subscriptions and seats that do not exist yet are not yours to propose or mention: when a stage is held by them, choose hold_reserved and leave founder_decision null. founder_decision is only for a stage a seat can move that has not moved in 14 days despite directives. Choose exactly one option id from input.options. Give your reasoning in at most eight sentences, citing the input numbers you relied on. Make one measurable prediction. Reply with a single JSON object matching output_schema and nothing else.',
    'input_fields', jsonb_build_array('date','goal','month_target','funnel','attainment','constraint','open_directives','options','plan_c_choice','marketing'),
    'output_schema', jsonb_build_object(
      'option_id', 'one of input.options[].id',
      'reasoning', 'string, 40-2000 characters, cites input numbers',
      'prediction', jsonb_build_object('measure_key','one of the measure keys in input.funnel','direction','min|max','value','number >= 0','by_date','YYYY-MM-DD, 1-30 days after input.date'),
      'directives', 'array of at most 3: {seat: sales_engineer|customer_support|accountant|it_engineer, stage, measure_key, direction, target >= 0, due_days 1-14, instruction <= 400 characters}',
      'founder_decision', 'null, or <= 300 characters naming the one decision only the founder can take'),
    'plan_c', 'If the slot is off, the call fails, or the answer fails validation, the coded decision already taken stands and the rejection is recorded on the plan.')
$fn$;
revoke execute on function public.fn_ceo_judgement_contract() from public, anon, authenticated;

create or replace function public.fn_ceo_judgement_request(p_plan_id bigint)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare p public.ceo_plan; c jsonb := public.fn_ceo_judgement_contract();
begin
  select * into p from public.ceo_plan where id = p_plan_id;
  if not found then return null; end if;
  return jsonb_build_object('contract', c->>'version', 'system', c->>'system', 'output_schema', c->'output_schema',
    'input', jsonb_build_object(
      'date', p.plan_date, 'goal', 'AED 1,000,000 cumulative reveal fees by 2027-08-31',
      'month_target', p.month_target, 'funnel', p.funnel - 'gates' || jsonb_build_object('founder_switches', p.funnel->'gates'),
      'attainment', p.decision->'attainment',
      'constraint', jsonb_build_object('stage', p.stage, 'label', p.decision->>'label', 'lever', p.decision->>'lever',
                                       'since', p.constraint_since, 'days', p.decision->'days_on_constraint', 'stalled', p.decision->'stalled'),
      'open_directives', (select coalesce(jsonb_agg(jsonb_build_object('seat', a.agent, 'stage', a.detail->>'stage', 'measure_key', a.detail->>'measure_key',
                                   'target', a.detail->'target', 'due_at', a.detail->>'due_at', 'reply', a.evidence)), '[]'::jsonb)
                            from public.agent_actions a where a.kind='handoff' and a.detail->>'type'='ceo.directive' and a.status='pending'),
      'options', p.decision->'options', 'plan_c_choice', p.decision->>'plan_c_choice',
      -- 22 Sep 2026 (instruction 721): the marketing seat's latest daily report, read not approved.
      'marketing', (select jsonb_build_object('report_date', m.report_date, 'no_data_yet', m.no_data_yet,
                                              'headline', m.figures->>'headline', 'measured', m.figures->'measured',
                                              'not_measured', m.figures->'not_measured')
                      from public.marketing_report m where m.report_date <= p.plan_date order by m.report_date desc limit 1)));
end $fn$;
revoke execute on function public.fn_ceo_judgement_request(bigint) from public, anon, authenticated;

-- ── 18. THE SEAT LISTS THAT ARE LITERALS NAME THE SIXTH SEAT ────────────────────────────────────
-- Copied from the live definitions (22 Sep 2026) with only the seat list changed, plus the marketing
-- achievement on the CEO's board and pg_temp pinned on fn_ceo_weekly_figures (it pinned 'public' alone).
create or replace function public.fn_ceo_seat_board(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  v_from timestamptz := now() - make_interval(days => greatest(1, coalesce(p_days, 7)));
  j jsonb;
begin
  select jsonb_build_object(
    'window_days', greatest(1, coalesce(p_days, 7)),
    'since', v_from,
    'seats', (
      select jsonb_object_agg(s.seat, jsonb_build_object(

        -- WHAT IT DID: every run, and every run that failed. Same source for all six, so the
        -- comparison between seats is honest.
        'runs',        (select count(*) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat and r.started_at >= v_from),
        'errors',      (select count(*) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat
                           and r.status = 'error' and r.started_at >= v_from),
        'last_seen',   (select max(r.started_at) from agent_runs r
                         where public.fn_run_seat(r.agent) = s.seat),

        -- WHAT IS WAITING ON IT: work assigned and not finished. This is the half the CEO had no
        -- sight of at all.
        'open_tasks',  (select count(*) from org_tasks t
                         where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),
        'oldest_open_task_days', (select round(extract(epoch from (now() - min(t.created_at)))/86400)
                         from org_tasks t
                        where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),

        -- WHAT IT FILED TO THE CEO, and whether the CEO has picked it up. An unread report is the
        -- CEO's own backlog, not the seat's.
        --
        -- THE NAME OF THIS FIGURE WAS WRONG AND THE FOUNDER CAUGHT IT. It read
        -- 'awaiting_my_acceptance', and on 9 September he read the board and asked "wait is the CEO
        -- basically waiting to approve the accountant report" -- a fair reading of that phrase, and
        -- not what the number means. Measured: three routines read accepted_at
        -- (fn_ceo_weekly_figures, fn_ceo_seat_board, fn_customer_mandatory_check) and all three only
        -- COUNT it for display. Nothing gates on it. Both accountant reports say in their own
        -- requested_outcome field "NOTHING IS REQUESTED", and one had already reached the founder.
        -- It is a read receipt, not an approval queue, and the label now says which. A number whose
        -- name implies work is blocked, on a board built so the chief executive knows what is
        -- waiting on whom, is worse than no number.
        'filed_to_ceo',    (select count(*) from support_ceo_report c where c.source_agent = s.seat),
        'filed_but_not_yet_read_by_ceo', (select count(*) from support_ceo_report c
                                    where c.source_agent = s.seat and c.accepted_at is null),

        -- WHAT IT ACHIEVED: the question this seat's own job answers.
        'achievement', case s.seat
          when 'accountant' then jsonb_build_object(
            'expense_records_with_a_document', (select count(*) from expense_entries where doc_path is not null),
            'journals_posted',                 (select count(*) from gl_journal where status = 'posted'),
            'weekly_reports_delivered',        (select count(*) from accountant_weekly_report where founder_submitted_at is not null))
          when 'customer_support' then jsonb_build_object(
            'conversations_answered',          (select count(*) from assistant_logs where created_at >= v_from),
            'questions_it_could_not_answer',   (select count(*) from sales_knowledge_gap where status = 'open'),
            'supplier_contacts_logged',        (select count(*) from supplier_response_watch))
          when 'sales_engineer' then jsonb_build_object(
            'assists_given',                   (select count(*) from sales_decision_log where created_at >= v_from),
            'quotes',                          (select count(*) from quotes),
            'comparisons',                     (select count(*) from quote_comparisons))
          when 'it_engineer' then jsonb_build_object(
            'findings_open',                   (select count(*) from it_watch_finding where status = 'open'),
            'findings_closed',                 (select count(*) from it_watch_finding where status = 'resolved'),
            'alerts_delivered',                (select count(*) from notifications
                                                 where kind like 'it_%' and status = 'sent'))
          -- 22 Sep 2026 (founder instruction 721): the marketing seat reports the overall picture to the CEO.
          -- Its reports are READ, never approved; 'read_by_ceo' counts the CEO's read receipts.
          when 'marketing' then jsonb_build_object(
            'reports_filed',                   (select count(*) from marketing_report),
            'reports_read_by_ceo',             (select count(*) from marketing_report where read_by_ceo_at is not null),
            'ad_spend_reported_aed',           (select coalesce(sum(amount_aed), 0) from ad_spend_reported),
            'latest_report',                   (select jsonb_build_object('date', m.report_date, 'headline', m.figures->'headline',
                                                                          'no_data_yet', m.no_data_yet)
                                                  from marketing_report m order by m.report_date desc limit 1))
          when 'ceo' then jsonb_build_object(
            'approvals_decided',               (select count(*) from ceo_approval),
            'reports_accepted',                (select count(*) from support_ceo_report where accepted_at is not null),
            'weekly_reports_delivered',        (select count(*) from ceo_weekly_report where founder_submitted_at is not null))
          else '{}'::jsonb end))
      from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) as seat) s),

    'basis', 'Every figure is a count of rows that exist, over the window for activity and lifetime '
          || 'for achievement. Nothing here is scored or rated. A zero means the thing has not '
          || 'happened, not that nobody counted it — the seats were created 7-9 September 2026 and '
          || 'the company has taken no revenue yet.'
  ) into j;
  return j;
end $fn$;
revoke execute on function public.fn_ceo_seat_board(integer) from public, anon, authenticated;

create or replace function public.fn_ceo_weekly_figures(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
declare
  v_prev_from date := p_from - (p_to - p_from) - 1;
  v_prev_to   date := p_from - 1;
  j jsonb;
begin
  select jsonb_build_object(
    'window', jsonb_build_object('from', p_from, 'to', p_to,
                                 'prior_from', v_prev_from, 'prior_to', v_prev_to),

    'money', jsonb_build_object(
      'revenue_week_aed',  (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted' and g.entry_date between p_from and p_to),
      'revenue_prior_aed', (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted' and g.entry_date between v_prev_from and v_prev_to),
      'revenue_life_aed',  (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted'),
      -- SPEND COMES FROM THE LEDGER, NOT FROM expense_entries. Those rows carry a raw amount in
      -- the currency the vendor billed (USD and AED are both present), so summing them would add
      -- dollars to dirhams. The GL is already converted and is the accountant's authoritative
      -- figure, which is also where revenue above is read from — one source, one basis.
      'spend_week_aed',    (select coalesce(sum(l.debit-l.credit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '6%' and g.status='posted' and g.entry_date between p_from and p_to),
      'spend_life_aed',    (select coalesce(sum(l.debit-l.credit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '6%' and g.status='posted'),
      'vat_position',      public.fn_accountant_vat_threshold_check(false)),

    'supply', jsonb_build_object(
      'leads_total',       (select count(*) from leads),
      'contactable',       (select count(*) from leads where email is not null and coalesce(invite_status,'') <> 'bounced'),
      'invited_ever',      (select count(*) from leads where invite_status is not null),
      'invited_week',      (select count(*) from leads where invited_at::date between p_from and p_to),
      'registered',        (select count(*) from leads where registration_status is not null),
      'verified',          (select count(*) from leads where verified),
      'matchable',         (select count(*) from supplier_capabilities where confirmed_at is not null),
      -- 14 Sep 2026: suppliers the sales engineer put on matching hold after three consecutive held
      -- quotes were left unanswered (founder_instruction #158). Only the founder lifts it (#160).
      'on_matching_hold',  (select count(*) from leads where matching_block_reason = 'collaboration_hold'),
      'days_since_last_invite', (select case when max(invited_at) is null then null
                                   else (current_date - max(invited_at)::date) end from leads)),

    'demand', jsonb_build_object(
      'customers',         (select count(*) from customers),
      'customers_real',    ((select public.fn_customer_counts())->>'substantiated')::int,
      'inquiries_week',    (select count(*) from inquiries where created_at::date between p_from and p_to),
      'inquiries_ever',    (select count(*) from inquiries),
      'quotes_ever',       (select count(*) from quotes),
      'comparisons_ever',  (select count(*) from quote_comparisons),
      'reveals_ever',      (select count(*) from transactions)),

    'seats', (select jsonb_object_agg(s.seat, jsonb_build_object(
                'runs_week', (select count(*) from agent_runs r
                               where regexp_replace(r.agent,'^fn:','') = s.seat
                                 and r.started_at::date between p_from and p_to),
                'errors_week', (select count(*) from agent_runs r
                               where regexp_replace(r.agent,'^fn:','') = s.seat
                                 and r.status = 'error' and r.started_at::date between p_from and p_to)))
              from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) as seat) s),

    'health', jsonb_build_object(
      'it_findings_open',   (select count(*) from it_watch_finding where status='open'),
      'it_alerts_week',     (select count(*) from notifications where kind like 'it_%' and created_at::date between p_from and p_to),
      'reports_awaiting_ceo',(select count(*) from support_ceo_report where accepted_at is null and status='sent'),
      'founder_instructions_open', (select count(*) from founder_instruction where status='open'))
  ) into j;
  return j;
end $fn$;
revoke execute on function public.fn_ceo_weekly_figures(date, date) from public, anon, authenticated;

create or replace function public.fn_it_handoff_sla_items(p_include_demo boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $fn$
  with h as (
    select a.id, a.agent, a.created_at, a.detail->>'type' t, a.detail ? 'replied_at' replied,
           coalesce(k.reply_within, interval '1 hour') w,
           f.closed_at f_closed,
           (f.issue_key is null or f.closed_at is not null
            or f.started_at > (a.detail->>'occurrence_started_at')::timestamptz) cleared
      from public.agent_actions a
      left join public.seat_handoff_kind k
        on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
      left join public.it_engineer_finding f
        on a.detail->>'type' = 'it.finding' and f.issue_key = a.detail->>'issue_key'
     where a.kind = 'handoff' and a.status in ('pending', 'failed')
       and a.detail->>'type' <> 'delivery.request'
       and (p_include_demo or (a.title not ilike '%ZZ DEMO%' and coalesce(a.detail->>'demo', 'false') <> 'true'))
  ), late as (
    select h.*, case
        when not h.replied and now() > h.created_at + h.w then 'unanswered'
        when h.replied and h.t = 'it.finding' and h.cleared
             and now() > greatest(h.created_at, coalesce(h.f_closed, h.created_at)) + h.w then 'unclosed'
        -- ponytail: other originator-closed types get a flat 24 h past their window, because
        -- fn_originators_reverify_handoffs escalates them to the CEO at the window first. Per-type
        -- rules belong in seat_handoff_kind if one of them ever needs a different allowance.
        when h.replied and h.t <> 'it.finding' and now() > h.created_at + h.w + interval '24 hours' then 'unclosed'
      end state
      from h)
  select coalesce(jsonb_agg(jsonb_build_object(
           'item', g.t || ':' || g.agent || ':' || g.state,
           'owner_seat', case when g.state = 'unanswered' and g.agent in ('ceo', 'customer_support', 'sales_engineer', 'accountant', 'marketing')
                              then g.agent else 'ceo' end,
           'subject', 'agent_actions',
           'title', g.n || ' ' || g.t || ' handoff(s) to ' || g.agent
                    || case g.state when 'unanswered' then ' have had no reply'
                       else ' were answered but never closed by the seat that sent them' end
                    || ' past the ' || g.w || ' window; the oldest is #' || g.oldest_id || ' from '
                    || to_char(g.oldest_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI') || ' Dubai',
           'blast', 'agent_facing', 'affected', g.n,
           'evidence', jsonb_build_object('state', g.state, 'type', g.t, 'seat', g.agent, 'reply_within', g.w::text,
                                          'handoff_ids', g.ids, 'oldest_at', g.oldest_at,
                                          'look_at', 'select id, detail, evidence from public.agent_actions where id in (<handoff_ids>)'))
           order by g.t, g.agent, g.state), '[]'::jsonb)
    from (select t, agent, state, min(w) w, count(*) n, min(id) oldest_id, min(created_at) oldest_at,
                 jsonb_agg(id order by id) ids
            from late where state is not null group by t, agent, state) g;
$fn$;
revoke execute on function public.fn_it_handoff_sla_items(boolean) from public, anon, authenticated;

-- ── 19. THE CLOSING ASSERTION. A seat that is not fully seated fails the apply instead of exiting 0. ──
-- It only reads. The behaviour (every conversation end to end on ZZ DEMO rows) is the probe's.
do $check$
declare
  v_names text; v_edge int; v_grants int; v_cred int; v_owner int; v_kinds int; v_policy boolean; v_step int;
  v_untagged int; v_pub jsonb; v_spend jsonb; v_refund jsonb; v_tables int; v_policies int;
begin
  select string_agg(role_id, ',' order by role_id) into v_names from public.org_role where status = 'active';
  select count(*) into v_edge from public.org_reporting_edge where child_role_id = 'marketing' and parent_role_id = 'ceo';
  select count(*) into v_grants from public.ceo_standing_grant where grantee_role_id = 'marketing' and active;
  select count(*) into v_cred from public.internal_credential where context = 'fn.marketing' and active and 'marketing' = any(scope);
  select count(*) into v_owner from public.function_owner where function_slug = 'marketing' and owner = 'marketing';
  select count(*) into v_kinds from public.seat_handoff_kind where 'marketing' in (from_seat, to_seat);
  select coalesce(bool_and(allowed_to_email and owner_role = 'marketing'), false) into v_policy
    from public.founder_mail_policy where kind = 'social_human_request';
  select count(*) into v_step from public.resilience_step where step = 'marketing';
  select count(*) into v_untagged from public.org_role, unnest(forbidden_decisions) f
   where role_id = 'marketing' and f !~ '^\[[a-z_]+\] ';
  select count(*) into v_tables from pg_class where relnamespace = 'public'::regnamespace and relrowsecurity
     and relname in ('marketing_report', 'ad_spend_reported');
  select count(*) into v_policies from pg_policies where schemaname = 'public' and tablename in ('marketing_report', 'ad_spend_reported');
  if v_names is distinct from 'accountant,ceo,customer_support,it_engineer,marketing,sales_engineer'
     or v_edge <> 1 or v_grants <> 4 or v_cred <> 1 or v_owner <> 1 or v_kinds <> 6 or not v_policy or v_step <> 1
     or v_untagged <> 0 or v_tables <> 2 or v_policies <> 2 then
    raise exception 'MARKETING SEAT NOT ESTABLISHED: roster=% edge=% grants=% cred=% owner=% kinds=% mail_policy=% step=% untagged=% rls=% policies=%',
      v_names, v_edge, v_grants, v_cred, v_owner, v_kinds, v_policy, v_step, v_untagged, v_tables, v_policies;
  end if;
  -- What it may do works; what it was not granted is refused; the other seats did not move.
  v_pub := public.fn_agent_may_act('marketing', 'publishing');
  v_spend := public.fn_agent_may_act('marketing', 'ad_spend', 1);
  v_refund := public.fn_agent_may_act('accountant', 'refund', 1);
  if (v_pub->>'may_act')::boolean is distinct from true or (v_spend->>'may_act')::boolean is distinct from false
     or (v_refund->>'route') is distinct from 'ceo_case_decision' then
    raise exception 'MARKETING AUTHORITY WRONG: publishing=% ad_spend=% accountant refund=%', v_pub, v_spend, v_refund;
  end if;
end
$check$;
