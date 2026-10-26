-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721164229   name: fn_split_inquiry_by_trade
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #80 — the customer chose "a specialist for each part". Create one child inquiry per trade under the
-- original, so each is matched and quoted independently while staying grouped for the customer.
-- The parent is retired from dispatch (rfq_ready=false) so it can never also be matched as a whole,
-- which would double-contact suppliers.
create or replace function public.fn_split_inquiry(p_parent uuid, p_trades text[])
returns table (child_id uuid, trade text)
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare p record; t text; new_id uuid; label text;
begin
  select * into p from public.inquiries where id = p_parent;
  if not found then raise exception 'inquiry % not found', p_parent; end if;
  if coalesce(array_length(p_trades,1),0) < 2 then raise exception 'split needs at least 2 trades'; end if;

  -- idempotent: never split the same parent twice
  if exists (select 1 from public.inquiries where parent_inquiry_id = p_parent) then
    return query select i.id, coalesce(i.trades[1], i.category) from public.inquiries i where i.parent_inquiry_id = p_parent;
    return;
  end if;

  foreach t in array p_trades loop
    select coalesce(tt.label, t) into label from public.taxonomy_trade tt where tt.code = t;
    insert into public.inquiries (
      customer_id, category, emirate, role_needed, raw_input, spec, summary, keywords,
      status, boq, budget, scope_type, trades, brief_source, drawing_file_path, drawing_file_name,
      drawing_redacted_paths, urgency, project_id, parent_inquiry_id, completeness, rfq_ready, provenance
    ) values (
      p.customer_id, t, p.emirate, p.role_needed, p.raw_input, p.spec,
      coalesce(label,t) || ' — ' || coalesce(p.summary, 'part of a combined request'),
      p.keywords, 'new', p.boq, p.budget, 'single', array[t], p.brief_source,
      p.drawing_file_path, p.drawing_file_name, p.drawing_redacted_paths, p.urgency,
      p.project_id, p_parent, p.completeness, false,
      coalesce(p.provenance,'{}'::jsonb) || jsonb_build_object('split_from', p_parent, 'split_trade', t, 'split_at', now())
    ) returning id into new_id;
    child_id := new_id; trade := t; return next;
  end loop;

  -- parent becomes the grouping record only: never dispatched itself
  update public.inquiries
     set scope_type = 'multi',
         trades = p_trades,
         rfq_ready = false,
         status = 'split',
         routing = coalesce(routing,'{}'::jsonb) || jsonb_build_object(
                     'outcome','split_by_trade','split_at',now(),'split_trades',to_jsonb(p_trades))
   where id = p_parent;
end $$;

comment on function public.fn_split_inquiry is
  'Customer chose specialist-per-trade. Creates one child inquiry per trade under the parent and retires the parent from dispatch so suppliers are never contacted twice for the same scope. Idempotent.';

-- Per-trade fanout must be lower than single-trade fanout, otherwise splitting a 4-trade job would
-- contact 20 suppliers where a combined job contacts 5. Already seeded as match_max_fanout_per_trade=3.
insert into public.decision_policy (key, value, description) values
 ('use_capability_matching','false'::jsonb,'Master switch for structured capability matching in route_inquiry. false = legacy vector/keyword retrieval. Flip to true to enable; flip back to roll back instantly.')
on conflict (key) do nothing;
