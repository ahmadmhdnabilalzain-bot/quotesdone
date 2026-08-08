-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709090556   name: knowledge_hybrid_publish_gate
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- high-stakes gate: regulations must be approved before they publish into kb_chunks
alter table public.regulations
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by text;

-- grandfather existing regulations as approved (trusted seed) BEFORE the trigger exists
update public.regulations set approved_at = coalesce(approved_at, now()), approved_by = coalesce(approved_by,'seed');

create or replace function public.trg_reg_gov_fn()
returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if TG_OP = 'INSERT' then
    NEW.approved_at := null; NEW.approved_by := null;
  elsif (coalesce(NEW.title,'') is distinct from coalesce(OLD.title,'')
      or coalesce(NEW.summary,'') is distinct from coalesce(OLD.summary,'')
      or coalesce(NEW.key_requirements::text,'') is distinct from coalesce(OLD.key_requirements::text,'')
      or coalesce(NEW.body,'') is distinct from coalesce(OLD.body,'')
      or coalesce(NEW.source_url,'') is distinct from coalesce(OLD.source_url,'')
      or coalesce(NEW.effective_date::text,'') is distinct from coalesce(OLD.effective_date::text,'')
      or coalesce(NEW.status,'') is distinct from coalesce(OLD.status,'')) then
    NEW.approved_at := null; NEW.approved_by := null;
  end if;
  return NEW;
end $$;
drop trigger if exists trg_reg_gov on public.regulations;
create trigger trg_reg_gov before insert or update on public.regulations for each row execute function public.trg_reg_gov_fn();

-- gate kb_sync: only approved active regulations become published chunks
create or replace function public.kb_sync()
 returns jsonb language plpgsql set search_path to 'public','pg_temp'
as $function$
declare n int;
begin
  delete from kb_chunks where source_kind in ('regulation','trade','material');
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'regulation', r.id::text, cat, r.title,
    coalesce(r.summary,'') || case when jsonb_array_length(coalesce(r.key_requirements,'[]'::jsonb))>0
      then E'\nKey requirements: ' || (select string_agg(x, '; ') from jsonb_array_elements_text(r.key_requirements) x) else '' end,
    r.authority || ' — ' || r.title || coalesce(' [' || r.source_url || ']','') || coalesce(' (effective ' || r.effective_date::text || ')',''),
    r.effective_date
  from regulations r
  left join lateral unnest(case when array_length(r.categories,1) is null then array[null::text] else r.categories end) as cat on true
  where r.status = 'active' and r.approved_at is not null;
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'trade', ak.id::text, ak.agent_key, ak.topic, ak.content,
    'QuotesDone trade knowledge: ' || coalesce(ak.agent_key,'') || ' / ' || coalesce(ak.topic,''), null
  from agent_knowledge ak;
  insert into kb_chunks(source_kind,source_id,category,title,content,citation,effective_date)
  select 'material', m.id::text, m.category, m.item,
    m.item || ' — ' || coalesce(m.properties::text,'') ||
      case when array_length(m.standards,1) is not null then E'\nStandards: ' || array_to_string(m.standards,', ') else '' end ||
      case when m.price_band is not null then E'\nPrice band: ' || m.price_band else '' end,
    'QuotesDone material library: ' || m.item, null
  from materials m;
  select count(*) into n from kb_chunks;
  return jsonb_build_object('chunks', n);
end $function$;

-- founder approval action for high-stakes knowledge
create or replace function public.fn_kb_gov_approve(p_kind text, p_id text, p_by text default 'founder')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare n int;
begin
  if p_kind = 'regulation' then
    update regulations set approved_at = now(), approved_by = p_by where id::text = p_id and approved_at is null;
    get diagnostics n = row_count;
    perform kb_sync();
    update agent_actions set status='approved', decided_at=now(), decided_by=p_by
      where kind='knowledge_approval' and detail->>'ref'=p_id and detail->>'kind'='regulation' and status in ('pending','needs_review');
    return jsonb_build_object('approved', n, 'kind', p_kind, 'id', p_id);
  end if;
  return jsonb_build_object('error','unsupported_kind', 'kind', p_kind);
end $$;
revoke all on function public.fn_kb_gov_approve(text,text,text) from anon, authenticated, public;
