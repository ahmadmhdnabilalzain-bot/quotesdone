-- ============================================================================
-- AUTONOMY ENGINE · FOUNDER REVIEW — exactly three gates, nothing else.
-- The founder reviews only: (1) marketing posts, (2) boost budgets, (3) refunds.
-- Everything else the staff ships automatically within the constitutional gates.
-- approve → ships; comment → back to the department to revise; reject → drop.
-- ============================================================================

alter table public.content_drafts add column if not exists review_status text default 'pending';
alter table public.content_drafts add column if not exists founder_comment text;
alter table public.content_drafts add column if not exists reviewed_at timestamptz;
update public.content_drafts set review_status='pending' where review_status is null and status='draft';

create table if not exists public.review_queue (
  id bigserial primary key,
  kind text not null, dept_key text, title text not null, summary text, payload jsonb,
  status text not null default 'pending', founder_comment text,
  created_at timestamptz default now(), decided_at timestamptz, decided_by text
);
alter table public.review_queue enable row level security;

insert into public.decision_policy(key, value, description) values
('founder_review_gates', '["marketing_post","boost_budget","refund"]'::jsonb, 'The ONLY work that requires founder review. Everything else the departments ship automatically within the constitutional gates.')
on conflict (key) do update set value=excluded.value, description=excluded.description, updated_at=now();

-- fn_review_pending(): unified founder review surface, computed live from the real sources.
create or replace function public.fn_review_pending()
returns jsonb language sql stable security definer set search_path to 'public','pg_temp' as $$
  select jsonb_build_object(
    'marketing_posts', coalesce((select jsonb_agg(jsonb_build_object('kind','marketing_post','ref_id',c.id,'title',c.title,'channel',c.channel,'body',c.body,'image_url',c.image_url,'created_at',c.created_at) order by c.created_at desc)
      from content_drafts c where c.status='draft' and coalesce(c.review_status,'pending')='pending'), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object('kind','refund','ref_id',t.id,'customer_id',t.customer_id,'reason',t.refund_reason,'requested_at',t.refund_requested_at) order by t.refund_requested_at desc)
      from transactions t where t.refund_status='requested'), '[]'::jsonb),
    'boost_budgets', coalesce((select jsonb_agg(jsonb_build_object('kind','boost_budget','ref_id',r.id,'title',r.title,'summary',r.summary,'payload',r.payload,'created_at',r.created_at) order by r.created_at desc)
      from review_queue r where r.kind='boost_budget' and r.status='pending'), '[]'::jsonb)
  );
$$;

-- fn_review_decide(kind, ref_id, decision, comment): approve | changes | reject → acts on the right source.
create or replace function public.fn_review_decide(p_kind text, p_ref_id bigint, p_decision text, p_comment text default null, p_by text default 'founder')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare dec text := lower(coalesce(p_decision,'')); ok boolean := false;
begin
  if dec not in ('approve','changes','reject') then return jsonb_build_object('error','decision must be approve|changes|reject'); end if;
  if p_kind = 'marketing_post' then
    update content_drafts set review_status = case dec when 'approve' then 'approved' when 'changes' then 'changes_requested' else 'rejected' end,
      founder_comment = coalesce(p_comment, founder_comment), reviewed_at = now() where id = p_ref_id and status='draft'; ok := found;
  elsif p_kind = 'refund' then
    update transactions set refund_status = case dec when 'approve' then 'approved' when 'reject' then 'declined' else 'requested' end,
      refund_note = coalesce(p_comment, refund_note), refund_resolved_at = case when dec in ('approve','reject') then now() else refund_resolved_at end
      where id = p_ref_id and refund_status='requested'; ok := found;
  elsif p_kind = 'boost_budget' then
    update review_queue set status = case dec when 'approve' then 'approved' when 'changes' then 'changes_requested' else 'rejected' end,
      founder_comment = coalesce(p_comment, founder_comment), decided_at = now(), decided_by = p_by where id = p_ref_id and status='pending'; ok := found;
  else return jsonb_build_object('error','unknown kind '||p_kind); end if;
  return jsonb_build_object('ok', ok, 'kind', p_kind, 'ref_id', p_ref_id, 'decision', dec);
end $$;
revoke all on function public.fn_review_decide(text,bigint,text,text,text) from public, anon;
