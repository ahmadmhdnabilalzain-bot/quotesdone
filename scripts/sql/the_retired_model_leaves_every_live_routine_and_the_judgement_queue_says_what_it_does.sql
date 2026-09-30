-- THE RETIRED MODEL LEAVES EVERY LIVE ROUTINE, AND THE JUDGEMENT QUEUE SAYS WHAT IT DOES.
-- Seat: it_engineer. 30 Sep 2026.
--
-- THE FOUNDER'S RULING (founder_instruction 1068, 30 Sep 2026): "GLM shouldn't be anywhere in the code."
-- And the clarification of the same day: every slot where it was a model choice is REPLACED by the right
-- model from his matrix (founder_instruction 1056), never simply removed, so no list gets shorter.
--
-- MEASURED BEFORE THIS FILE (production, 30 Sep 2026):
--   * z-ai/glm-5.3-flash: model_registry active+approved, 0 model_policy routes name it (primary or
--     fallback) since 1056, 0 ai_cost_log rows mention it, 0 review_pool rows; one model_rate row and one
--     llm_route_health row (held since 23 Sep, total_ok 0). Only review_pool holds a foreign key to
--     model_registry, so nothing historical needs the row: it is DELETED, not just switched off.
--   * 12 routines name it: nine carry it in their name (the judgement queue of 24 Sep, built when the queue
--     ran on that model - since 1056 it runs the routine class on google/gemini-3.8-flash), and three in
--     their body: fn_ai_route_review_for (a hard-coded last-resort family), fn_support_wire_email (the
--     queued-mail mark) and fn_quote_spec_mismatches (reads the queue table).
--   * one table (2 queued rows kept), its sequence, 3 indexes, 5 constraints, 1 policy, 2 triggers,
--     1 table_export_registry row, 1 inbound_messages row carrying the queued mark, and 26 model_policy
--     rationales plus 2 model_registry notes and 1 model_rate note quoting the old routing as current.
--
-- WHAT THIS CHANGES (every rename keeps the object, so data and grants stay; CREATE OR REPLACE keeps the ACL):
--   table     glm_judgement                  -> routine_judgement (sequence, indexes, constraints, policy)
--   routine   fn_glm_judgement_enqueue       -> fn_routine_judgement_enqueue
--             fn_glm_judgement_due           -> fn_routine_judgement_due
--             fn_glm_judgement_resolve       -> fn_routine_judgement_resolve
--             fn_glm_judgement_defer         -> fn_routine_judgement_defer
--             fn_glm_quote_spec_supersede    -> fn_routine_quote_spec_supersede
--             fn_glm_taxonomy_trades         -> fn_taxonomy_trades_active
--             fn_glm_sender_known            -> fn_mail_sender_known
--             trg_glm_repeat_request_enqueue -> trg_routine_repeat_request_enqueue
--             trg_glm_trade_words_enqueue    -> trg_routine_trade_words_enqueue
--   trigger   z20_glm_repeat_request_enqueue -> z20_routine_repeat_request_enqueue (still first of the z-triggers)
--             z20_glm_trade_words_enqueue    -> z20_routine_trade_words_enqueue
--   value     inbound_messages.ai_category 'glm_queued' -> 'routine_queued' (and every reader of it)
--   written   plausibility duplicate_by 'glm' -> 'routine_judgement'; decided_by 'sales_engineer:glm' ->
--             'sales_engineer:routine_judgement'; detail key glm_judgement_id -> routine_judgement_id
--   router    fn_ai_route_review_for's built-in last-resort families. The retired model's slot is REPLACED by
--             deepseek/deepseek-v4.1-flash (1056's plan B for every seat but ceo and sales_engineer: the
--             cheapest live family), and openai/gpt-6-luna and anthropic/claude-opus-5.5 are added after it, so
--             the list names every live family - Google, DeepSeek, Qwen, OpenAI, Anthropic - and the
--             cross-family rule always has an option. Opus is last: the most expensive, a true last resort.
--   catalogue the model_registry row, its model_rate row and its llm_route_health row are deleted; the prose
--             that quoted the old routing as current names it as the 841 routing retired by 1068.
--
-- WHAT THIS DOES NOT CHANGE: no model_policy route (none named it), the model hold (still on), the review
-- pool, or any applied file (history stays as it was). The edge functions that call the renamed routines
-- (email_triage, quote_compare, resilience_ping via _shared/routine_judgements.ts) change in the SAME PR and
-- deploy right after this applies.
--
-- APPLIED 30 Sep 2026 BEFORE MERGE, NOT BY CHOICE: scripts/checks/every_model_class_is_on_the_founders_matrix.test.mjs
-- replays every pending file that touches model_policy verbatim, in one request, ahead of a probe that raises. This
-- file carried its own begin/commit, so the COMMIT ran before the raise and the "aborted" replay committed it. It
-- was read back PROBE OK, the three callers were deployed at once, and the note moved to MANIFEST in the same PR.
-- The replay is fixed in the same PR (it strips a file's own transaction statements).
-- Prevented by: scripts/checks/the_retired_model_is_named_nowhere_in_live_code.test.mjs (repository and live
--   routine bodies), scripts/checks/four_routine_judgements_run_on_the_routine_class_and_never_word_match.test.mjs,
--   supabase/functions/_shared/routine_judgements.test.ts. Ends in a PROBE verdict row.

begin;

-- ── the queue and the routines: rename (keeps the rows and the ACL), then each body under its new name ──────
-- RE-RUNNABLE: production took this file on 30 Sep 2026 before merge (header), so the release's bookkeeping apply
-- finds everything already renamed. The renames run only while the old table still exists; every statement after
-- this block is idempotent (create or replace, and updates/deletes whose WHERE no longer matches).
do $rename$
begin
  if to_regclass('public.glm_judgement') is null then return; end if;
  alter table public.glm_judgement rename to routine_judgement;
  alter sequence public.glm_judgement_id_seq rename to routine_judgement_id_seq;
  alter table public.routine_judgement rename constraint glm_judgement_pkey to routine_judgement_pkey;
  alter table public.routine_judgement rename constraint glm_judgement_kind_subject_key_key to routine_judgement_kind_subject_key_key;
  alter table public.routine_judgement rename constraint glm_judgement_kind_check to routine_judgement_kind_check;
  alter table public.routine_judgement rename constraint glm_judgement_subject_key_check to routine_judgement_subject_key_check;
  alter table public.routine_judgement rename constraint glm_judgement_status_check to routine_judgement_status_check;
  alter index public.glm_judgement_due_idx rename to routine_judgement_due_idx;
  alter policy glm_judgement_service_role_only on public.routine_judgement rename to routine_judgement_service_role_only;
  alter function public.fn_glm_judgement_enqueue(text, text, jsonb) rename to fn_routine_judgement_enqueue;
  alter function public.fn_glm_judgement_due(integer, bigint[]) rename to fn_routine_judgement_due;
  alter function public.fn_glm_judgement_resolve(bigint, jsonb, text) rename to fn_routine_judgement_resolve;
  alter function public.fn_glm_judgement_defer(bigint, text, boolean) rename to fn_routine_judgement_defer;
  alter function public.fn_glm_quote_spec_supersede(text, text[]) rename to fn_routine_quote_spec_supersede;
  alter function public.fn_glm_taxonomy_trades() rename to fn_taxonomy_trades_active;
  alter function public.fn_glm_sender_known(text) rename to fn_mail_sender_known;
  alter function public.trg_glm_repeat_request_enqueue() rename to trg_routine_repeat_request_enqueue;
  alter function public.trg_glm_trade_words_enqueue() rename to trg_routine_trade_words_enqueue;
  alter trigger z20_glm_repeat_request_enqueue on public.inquiries rename to z20_routine_repeat_request_enqueue;
  alter trigger z20_glm_trade_words_enqueue on public.taxonomy_trade_proposal rename to z20_routine_trade_words_enqueue;
end $rename$;

-- The export registry row follows the table (production ran an equivalent UPDATE of table_name; this is the shape
-- scripts/lib/table_export_registry.mjs replays).
delete from public.table_export_registry where table_name = 'glm_judgement';
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('routine_judgement', true, 'decision', 'backlog decided 29 Sep 2026, exported: model judgements and their results (2 rows)', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;

create or replace function public.fn_routine_judgement_enqueue(p_kind text, p_subject_key text, p_input jsonb)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint;
begin
  insert into public.routine_judgement (kind, subject_key, input) values (p_kind, p_subject_key, p_input)
  on conflict (kind, subject_key) do nothing returning id into v_id;
  if v_id is null then select id into v_id from public.routine_judgement where kind = p_kind and subject_key = p_subject_key; end if;
  return v_id;
end $fn$;

create or replace function public.fn_routine_judgement_due(p_limit integer default 5, p_ids bigint[] default null::bigint[])
returns setof public.routine_judgement
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return query
  update public.routine_judgement g set leased_until = now() + interval '5 minutes'
   where g.id in (select q.id from public.routine_judgement q
                   where q.status = 'queued' and (q.leased_until is null or q.leased_until < now())
                     and (p_ids is null or q.id = any(p_ids))
                   order by q.id limit greatest(1, least(coalesce(p_limit, 5), 50))
                   for update skip locked)
  returning g.*;
end $fn$;

create or replace function public.fn_routine_quote_spec_supersede(p_quote_id text, p_keep text[])
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n integer;
begin
  update public.routine_judgement set status = 'superseded', leased_until = null, decided_at = now()
   where kind = 'quote_spec_match' and input->>'quote_id' = p_quote_id
     and status in ('queued', 'done', 'failed') and not (subject_key = any(coalesce(p_keep, '{}'::text[])));
  get diagnostics n = row_count;
  return n;
end $fn$;

create or replace function public.fn_quote_spec_mismatches(p_quote_id text)
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'quote_id', p_quote_id,
    'pending', count(*) filter (where g.status = 'queued'),
    'unread', coalesce(sum(jsonb_array_length(g.input->'cells')) filter (where g.status = 'failed'), 0),
    'mismatches', coalesce(jsonb_agg(v) filter (where g.status = 'done' and (v->>'mismatch')::boolean), '[]'::jsonb),
    'meets', count(v) filter (where g.status = 'done' and not (v->>'mismatch')::boolean))
  from public.routine_judgement g
  left join lateral jsonb_array_elements(coalesce(g.result->'cells', '[]'::jsonb)) v on true
  where g.kind = 'quote_spec_match' and g.input->>'quote_id' = p_quote_id;
$fn$;

create or replace function public.fn_taxonomy_trades_active()
returns jsonb
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) order by sort, code), '[]'::jsonb)
    from public.taxonomy_trade where active;
$fn$;

create or replace function public.fn_mail_sender_known(p_email text)
returns text
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare e text := lower(btrim(coalesce(p_email, '')));
begin
  if e = '' then return null; end if;
  if exists (select 1 from public.app_secrets s, unnest(string_to_array(lower(s.value), ',')) a
              where s.key in ('admin_emails', 'expense_forwarders', 'founder_email') and btrim(a) = e) then return 'staff'; end if;
  if exists (select 1 from public.customers where lower(email) = e) then return 'customer'; end if;
  if exists (select 1 from public.leads where lower(email) = e) then return 'supplier'; end if;
  return null;
end $fn$;

create or replace function public.trg_routine_repeat_request_enqueue()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare p record;
begin
  if NEW.customer_id is null or btrim(coalesce(NEW.summary, '')) = ''
     or coalesce((NEW.plausibility->>'possible_duplicate')::boolean, false) then return NEW; end if;
  select i.id, i.summary into p from public.inquiries i
   where i.customer_id = NEW.customer_id and i.id <> NEW.id
     and i.created_at > now() - interval '30 minutes'
     and coalesce(i.category, '') = coalesce(NEW.category, '')
     and btrim(coalesce(i.summary, '')) <> ''
   order by i.created_at desc limit 1;
  if p.id is not null then
    perform public.fn_routine_judgement_enqueue('repeat_request', NEW.id::text,
      jsonb_build_object('inquiry_id', NEW.id, 'earlier_id', p.id, 'earlier', left(p.summary, 2000), 'later', left(NEW.summary, 2000),
                         'category', NEW.category));
  end if;
  return NEW;
end $fn$;

create or replace function public.trg_routine_trade_words_enqueue()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if NEW.status = 'pending' then
    perform public.fn_routine_judgement_enqueue('supplier_trade_words', NEW.id::text,
      jsonb_build_object('proposal_id', NEW.id, 'supplier_id', NEW.supplier_id,
                         'words', coalesce(NEW.label_en, '') || case when NEW.label_ar is not null then ' / ' || NEW.label_ar else '' end));
  end if;
  return NEW;
end $fn$;

create or replace function public.fn_routine_judgement_defer(p_id bigint, p_error text, p_counts boolean)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare g public.routine_judgement;
begin
  update public.routine_judgement
     set leased_until = null, last_error = left(p_error, 500),
         attempts = attempts + case when p_counts then 1 else 0 end,
         status = case when p_counts and attempts + 1 >= 3 then 'failed' else status end,
         decided_at = case when p_counts and attempts + 1 >= 3 then now() else decided_at end
   where id = p_id and status = 'queued'
  returning * into g;
  if g.id is null or g.status <> 'failed' then return; end if;
  -- THE TERMINAL STATE HANDS EACH KIND BACK TO ITS OWNER: three failed readings never leave anything waiting on a
  -- judgement that will not come.
  if g.kind = 'unknown_sender_mail' then
    -- The mail leaves the 'routine_queued' mark (which email_triage skips) and goes to a person's review, unread.
    update public.inbound_messages set ai_category = 'other', ai_summary = 'Not read: the routine model could not judge this mail after 3 tries.', triaged_at = now()
     where id = (g.input->>'message_id')::bigint and triaged_at is null;
    -- 28 Sep 2026: not when customer_support already answered it (the founder: no person unless asked for).
    if not exists (select 1 from public.inbound_messages where id = (g.input->>'message_id')::bigint and replied_at is not null) then
    insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
    values ('email', 'inbound_review', 'pending', 'low',
            left('Inbox (unknown sender, unread): ' || coalesce(g.input->>'subject', '(no subject)'), 70),
            'The routine model could not read this mail from an unknown sender after 3 tries. Read it and reply from the Inbox.',
            'inbound_messages', g.input->>'message_id',
            jsonb_build_object('from', g.input->>'from', 'routine_judgement_id', g.id, 'last_error', g.last_error));
    end if;
  elsif g.kind = 'supplier_trade_words' then
    -- The proposal stays pending for the sales engineer, saying why it was not offered.
    update public.taxonomy_trade_proposal set note = coalesce(note || ' ', '') || '[The routine model could not map these words after 3 tries; decide by hand.]'
     where id = (g.input->>'proposal_id')::bigint and status = 'pending';
  end if;
  -- repeat_request: the inquiry simply stays unflagged (a flag only marks review).
  -- quote_spec_match: fn_quote_spec_mismatches reports the cells as 'unread', never as meeting the request.
end $fn$;

create or replace function public.fn_routine_judgement_resolve(p_id bigint, p_result jsonb, p_model text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare g public.routine_judgement; v_effect text := 'recorded'; v_codes text[]; v_n integer;
begin
  update public.routine_judgement set status = 'done', result = p_result, model = p_model, decided_at = now(), leased_until = null
   where id = p_id and status = 'queued' returning * into g;
  if g.id is null then return jsonb_build_object('ok', false, 'reason', 'not_queued'); end if;

  if g.kind = 'repeat_request' and p_result->>'verdict' = 'same' then
    update public.inquiries
       set plausibility = coalesce(plausibility, '{}'::jsonb) || jsonb_build_object('possible_duplicate', true,
             'duplicate_of', g.input->>'earlier_id', 'duplicate_by', 'routine_judgement', 'routine_judgement_id', g.id)
     where id::text = g.input->>'inquiry_id'
       and not coalesce((plausibility->>'possible_duplicate')::boolean, false);
    v_effect := 'inquiry_flagged';

  elsif g.kind = 'supplier_trade_words' then
    -- Exact codes only: a code the taxonomy does not hold is never written (the caller already refused it; this
    -- is the second door).
    select array_agg(c) into v_codes from jsonb_array_elements_text(coalesce(p_result->'codes', '[]'::jsonb)) c
     where exists (select 1 from public.taxonomy_trade t where t.code = c and t.active);
    v_n := coalesce(array_length(v_codes, 1), 0);
    if v_n = 1 then
      update public.taxonomy_trade_proposal
         set status = 'map_offered', mapped_to = v_codes[1], decided_at = now(), decided_by = 'sales_engineer:routine_judgement',
             note = 'Offered to the supplier to confirm: ' || v_codes[1] || '. ' || coalesce(p_result->>'why', '')
       where id = (g.input->>'proposal_id')::bigint and status = 'pending';
      v_effect := 'map_offered';
    else
      update public.taxonomy_trade_proposal
         set note = case when v_n > 1
                      then 'Names several exact trades (' || array_to_string(v_codes, ', ') || '). Ask the supplier: '
                      else 'Names no exact taxonomy trade. Ask the supplier: ' end
                    || coalesce(nullif(p_result->>'ask', ''), 'which of our trades is this work?')
       where id = (g.input->>'proposal_id')::bigint and status = 'pending';
      v_effect := case when v_n > 1 then 'ask_several' else 'ask_none' end;
    end if;

  elsif g.kind = 'unknown_sender_mail' then
    update public.inbound_messages
       set ai_category = left(coalesce(p_result->>'category', 'other'), 40), ai_summary = left(p_result->>'summary', 500),
           triaged_at = now()
     where id = (g.input->>'message_id')::bigint and triaged_at is null;
    -- The same review item email_triage files for a drafted mail, so customer_support sees it; spam files nothing.
    -- 28 Sep 2026: nor a mail customer_support already answered (the founder: no person unless asked for).
    if coalesce(p_result->>'category', 'other') <> 'spam'
       and not exists (select 1 from public.inbound_messages where id = (g.input->>'message_id')::bigint and replied_at is not null) then
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, target_table, target_id, detail)
      values ('email', 'inbound_review', 'pending', 'low',
              left('Inbox (unknown sender): ' || coalesce(g.input->>'subject', '(no subject)'), 70) || ' - ' || coalesce(p_result->>'category', 'other'),
              'Unknown sender, read by the routine model. Review and reply from the Inbox.', 'inbound_messages', g.input->>'message_id',
              jsonb_build_object('from', g.input->>'from', 'category', p_result->>'category', 'summary', p_result->>'summary', 'routine_judgement_id', g.id));
    end if;
    v_effect := 'mail_triaged';
  end if;
  return jsonb_build_object('ok', true, 'effect', v_effect);
end $fn$;

-- ── the queued-mail mark, and its one reader in the database ─────────────────────────────────────────────
update public.inbound_messages set ai_category = 'routine_queued' where ai_category = 'glm_queued';

create or replace function public.fn_support_wire_email()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_from text := lower(substring(coalesce(new.from_email, '') from '([^<>\s"]+@[^<>\s"]+)'));
        v_kind text := 'unknown'; v_id text; v_first text;
begin
  if v_from is null or v_from ~ '@(mail\.)?quotesdone\.(com|ae)$' then return null; end if;
  if coalesce(new.owner_role, 'customer_support') <> 'customer_support' then return null; end if;
  begin
    select 'customer', c.id::text into v_kind, v_id from public.customers c where lower(btrim(c.email)) = v_from limit 1;
    if v_id is null then
      select 'supplier', l.id::text into v_kind, v_id from public.leads l where lower(btrim(l.email)) = v_from order by l.id limit 1;
    end if;
    v_kind := coalesce(v_kind, 'unknown');
    if new.triaged_at is not null and old.triaged_at is null
       and coalesce(new.ai_category, '') not in ('spam', 'no_auto_reply', 'routine_queued') then
      v_first := substring(coalesce(new.body, '') from '^\s*([^\r\n]*)');
      perform public.fn_support_touch('email', 'in', v_kind, v_id, v_from, null,
                                      coalesce(new.subject, '') || E'\n' || coalesce(new.body, ''), v_first, null);
    end if;
    if new.replied_at is not null and old.replied_at is null then
      perform public.fn_support_touch('email', 'out', v_kind, v_id, v_from);
    end if;
  exception when others then
    raise warning 'fn_support_wire_email: inbound_messages % not recorded on a case: %', new.id, sqlerrm;
  end;
  return null;
end $fn$;

-- ── the review router: every last-resort family is a live one ───────────────────────────────────────────
create or replace function public.fn_ai_route_review_for(p_task_class text, p_counterpart_model text, p_agent_key text default null::text, p_fn text default null::text, p_dept_key text default null::text, p_require_caps text[] default null::text[])
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_names text[]; v_fams text[] := '{}'; v_unknown text[] := '{}'; v_n text; v_f text; v_cp text;
  v_base jsonb; v_rej jsonb := '[]'::jsonb;
  v_pick text; v_pick_fam text; v_fb text; v_tier text;
  v_vis boolean := 'vision' = any (coalesce(p_require_caps, '{}'));
  v_aud boolean := 'audio'  = any (coalesce(p_require_caps, '{}'));
  v_tls boolean := 'tools'  = any (coalesce(p_require_caps, '{}'));
  c record;
begin
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter (where btrim(x) <> ''), '{}') into v_names
    from unnest(string_to_array(coalesce(p_counterpart_model, ''), ',')) x;
  v_cp := array_to_string(v_names, ',');
  foreach v_n in array v_names loop
    continue when v_n = 'deterministic';
    select lower(btrim(r.provider)) into v_f from public.model_registry r where r.model_id = v_n;
    if v_f is null then v_unknown := v_unknown || v_n; else v_fams := array(select distinct unnest(v_fams || v_f)); end if;
  end loop;

  if cardinality(v_names) = 0 or cardinality(v_unknown) > 0 then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true, 'unknown_author', true,
      'task_class', p_task_class, 'author_model', v_cp,
      'why', 'AUTHOR UNKNOWN: ' || coalesce(nullif(array_to_string(v_unknown, ', '), ''), '(none given)')
             || ' is not in model_registry, so its family is unknown and independence cannot be proved. A data defect in '
             || 'what the caller recorded about the author, not a missing reviewer.');
  end if;

  v_base := public.fn_ai_route(p_task_class, p_dept_key, null, p_fn, false, p_require_caps, p_agent_key);
  if not coalesce((v_base->>'use_llm')::boolean, false) then
    return v_base || jsonb_build_object('author_model', v_cp, 'author_family', to_jsonb(v_fams));
  end if;
  if cardinality(v_fams) = 0 then
    return v_base || jsonb_build_object('author_model', 'deterministic', 'author_family', '[]'::jsonb, 'independent', true,
      'reviewer_tier', 'standard', 'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: the author is deterministic code, not a model');
  end if;

  for c in
    -- 1056: the pair of the seat's own row for this review class when the seat has one ('<seat>__<class>'),
    -- otherwise the class's own - never the general_drafting row a missing class falls back to
    with pol as (select model_primary, model_fallback from public.model_policy
                  where task_class = case when right(coalesce(v_base->>'policy_class', ''), length(v_base->>'task_class') + 2)
                                                = '__' || (v_base->>'task_class')
                                          then v_base->>'policy_class' else v_base->>'task_class' end),
    cand as (
      -- 1056: the class's own pair first (primary, then its named fallback), then the pool as depth
      select pol.model_primary model_id, 0 ord from pol
      union all select pol.model_fallback, 1 from pol
      union all select p.model_id, 10 + p.rank from public.review_pool p where p.active
      -- 1068 (30 Sep 2026): the last-resort families are the matrix's live ones, cheapest first and Opus last.
      union all select 'google/gemini-3.8-flash', 2000000
      union all select 'deepseek/deepseek-v4.1-flash', 2000001
      union all select 'qwen/qwen3.7-plus', 2000002
      union all select 'openai/gpt-6-luna', 2000003
      union all select 'anthropic/claude-opus-5.5', 2000004)
    select d.model_id, d.ord, lower(btrim(r.provider)) provider, coalesce(r.active and r.approved, false) reg_ok,
           (not v_vis or coalesce(r.supports_vision, false)) and (not v_aud or coalesce(r.supports_audio, false))
             and (not v_tls or coalesce(r.supports_tools, false)) caps_ok,
           h.model_id is not null measured,
           coalesce(h.open_until > now() and h.opened_class is not null, false) tripped
      from (select model_id, min(ord) ord from cand where model_id is not null and model_id <> 'none' group by model_id) d
      left join public.model_registry r on r.model_id = d.model_id
      left join public.llm_route_health h on h.model_id = d.model_id
     order by d.ord, d.model_id
  loop
    if c.provider is null then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'not in model_registry');
    elsif c.provider = any (v_fams) then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'same family as an author (' || c.provider || ')');
    elsif not c.reg_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'inactive or unapproved in model_registry');
    elsif not c.caps_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'lacks a required capability (' || array_to_string(p_require_caps, '+') || ')');
    elsif not c.measured then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'no llm_route_health row: unmeasured is not healthy');
    elsif c.tripped then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'breaker tripped by real failures');
    elsif v_pick is null then
      v_pick := c.model_id; v_pick_fam := c.provider;
      v_tier := case when c.ord >= 2000000 then 'third_family_fallback' else 'standard' end;
    elsif v_fb is null and (c.ord < 2000000 or v_tier = 'third_family_fallback') then
      v_fb := c.model_id;
    end if;
  end loop;

  if v_pick is null then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true,
      'task_class', v_base->>'task_class', 'author_model', v_cp, 'author_family', to_jsonb(v_fams), 'pool_rejected', v_rej,
      'why', 'NO INDEPENDENT REVIEWER: no active, healthy, capable candidate outside the ' || array_to_string(v_fams, '/')
             || ' families, not even a last-resort family. The review is HELD, never run on an author''s family.');
  end if;

  return v_base || jsonb_build_object(
    'model', v_pick, 'fallback', v_fb,
    'in_per_mtok_usd', (select in_per_mtok_usd from public.model_registry where model_id = v_pick),
    'out_per_mtok_usd', (select out_per_mtok_usd from public.model_registry where model_id = v_pick),
    'reviewer_family', v_pick_fam, 'reviewer_tier', v_tier, 'author_model', v_cp, 'author_family', to_jsonb(v_fams),
    'independent', true, 'pool_rejected', v_rej,
    'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: author wrote on ' || v_cp
           || ' (' || array_to_string(v_fams, '/') || '), reviewer routed to ' || v_pick || ' (' || v_pick_fam || ')'
           || coalesce(', fallback ' || v_fb, ', no fallback outside ' || array_to_string(v_fams, '/')));
end $fn$;

-- ── the catalogue: the retired model leaves it ──────────────────────────────────────────────────────────
delete from public.llm_route_health where model_id = 'z-ai/glm-5.3-flash';
delete from public.model_rate where model = 'z-ai/glm-5.3-flash';
delete from public.model_registry where model_id = 'z-ai/glm-5.3-flash';

-- The prose that still quoted the 841 routing as current now says it was retired.
update public.model_policy
   set rationale = regexp_replace(regexp_replace(regexp_replace(rationale,
         '(z-ai/)?glm[- ]?5\.3[- ]?flash', 'the 841 model (retired by 1068)', 'gi'),
         '\mGLM\M', 'the 841 model', 'g'), 'glm', 'the 841 model', 'gi')
       || ' [30 Sep 2026, founder_instruction 1068: the 841 model is retired and named nowhere; this class runs on its 1056 matrix pair, '
       || model_primary || ' then ' || coalesce(model_fallback, 'no fallback') || '.]'
 where rationale ilike '%glm%';
update public.model_registry
   set note = regexp_replace(regexp_replace(note, '(z-ai/)?glm[- ]?5\.3[- ]?flash', 'the 841 model (retired by 1068)', 'gi'), 'glm', 'the 841 model', 'gi')
 where note ilike '%glm%';
update public.model_rate
   set note = regexp_replace(regexp_replace(note, '(z-ai/)?glm[- ]?5\.3[- ]?flash', 'the 841 model (retired by 1068)', 'gi'), 'glm', 'the 841 model', 'gi')
 where note ilike '%glm%';

-- ── PROBE: the result, read back (no rows written; the queue is exercised by the rehearsal in the PR) ─────
with c as (
  select
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and (p.proname ilike '%glm%' or p.prosrc ilike '%glm%')) as routines_naming_it,
    (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname ilike '%glm%') as relations_naming_it,
    (select count(*) from pg_trigger where tgname ilike '%glm%') as triggers_naming_it,
    (select count(*) from public.model_registry where model_id ilike '%glm%' or note ilike '%glm%') +
    (select count(*) from public.model_policy where model_primary ilike '%glm%' or model_fallback ilike '%glm%' or rationale ilike '%glm%') +
    (select count(*) from public.model_rate where model ilike '%glm%' or note ilike '%glm%') +
    (select count(*) from public.llm_route_health where model_id ilike '%glm%') as catalogue_naming_it,
    (select count(*) from public.inbound_messages where ai_category ilike '%glm%') as marks_naming_it,
    (select count(*) from public.routine_judgement) as queue_rows_kept,
    (select count(*) from pg_proc where proname in ('fn_routine_judgement_enqueue', 'fn_routine_judgement_due',
       'fn_routine_judgement_resolve', 'fn_routine_judgement_defer', 'fn_routine_quote_spec_supersede', 'fn_taxonomy_trades_active',
       'fn_mail_sender_known', 'trg_routine_repeat_request_enqueue', 'trg_routine_trade_words_enqueue')
       and has_function_privilege('anon', oid, 'execute')) as anon_can_execute,
    (select count(*) from public.model_registry r join public.llm_route_health h using (model_id)
      where r.active and r.approved and r.model_id in ('google/gemini-3.8-flash', 'deepseek/deepseek-v4.1-flash',
        'openai/gpt-6-luna', 'anthropic/claude-opus-5.5')) as last_resort_live
)
select case when routines_naming_it = 0 and relations_naming_it = 0 and triggers_naming_it = 0 and catalogue_naming_it = 0
             and marks_naming_it = 0 and queue_rows_kept >= 2 and anon_can_execute = 0 and last_resort_live = 4
            then 'PROBE OK :: the retired model is named in no routine, relation, trigger or catalogue row; queue kept ('
                 || queue_rows_kept || ' rows); 4 live last-resort families'
            else 'PROBE FAILED :: ' || jsonb_build_object('routines', routines_naming_it, 'relations', relations_naming_it,
                 'triggers', triggers_naming_it, 'catalogue', catalogue_naming_it, 'marks', marks_naming_it,
                 'queue', queue_rows_kept, 'anon', anon_can_execute, 'last_resort_live', last_resort_live)::text end as verdict
  from c;

commit;
