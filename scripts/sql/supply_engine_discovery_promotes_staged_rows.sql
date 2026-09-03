-- SUPPLIER DISCOVERY WITHOUT A SCRAPER (3 Sep 2026).
--
-- What the scorer found (s26-discover-suppliers): 0 scrape runs in 30 days (last ever 19 Jun), 1 new
-- lead in 30 days, and 13,123 rows sitting in yello_staging — 11,152 of them with an email address —
-- that nothing had ever promoted into leads. Apify scraping is deliberately paused until ~Feb 2027,
-- so discovery has to come from what is already paid for: the staged directory rows.
--
-- fn_supplier_discovery_promote is that discovery. Every run:
--   1. records itself in scrape_runs (actor 'yello_staging:promote') — a discovery run is a run, and
--      the row carries requested / fetched (candidates) / inserted like a scraper's would;
--   2. picks up to p_limit staged rows with an email that no lead carries (lower(email), company
--      name and phone are all checked; uq_leads_email_lower would refuse the first anyway), thinnest
--      catalogue category first so the rows land where coverage is worst;
--   3. inserts them as leads (source 'yello_staging'), with invite_trades normalised so the invite
--      plan can target them, and classifies each into the catalogue through the same lexicon
--      (category_keyword, method keyword_v1) that classified the original 12,566;
--   4. marks the staged row 'promoted' (or 'duplicate' when a lead already had it) so a run never
--      re-reads what it already did;
--   5. classifies up to p_classify existing leads the lexicon has never been run over — approved
--      suppliers first. Measured 3 Sep: the ONE approved, matchable supplier sits in no category at
--      all, which is why every category read 0 matchable. lead_category_scan remembers which leads
--      were scanned so an unmatched lead is not re-scanned every day.
--
-- fn_category_classify is the lexicon applied to one text: LIKE pre-filter over the 1,839 patterns,
-- word-boundary confirmation on the hits, weights summed per slug (negatives subtract), slugs at 3
-- or more returned. Deterministic, no model, same evidence column as the original classification.
--
--   node scripts/apply_sql.mjs scripts/sql/supply_engine_discovery_promotes_staged_rows.sql --apply --ddl

create table if not exists public.lead_category_scan (
  lead_id    bigint primary key references public.leads(id) on delete cascade,
  scanned_at timestamptz not null default now(),
  matched    int not null default 0
);
alter table public.lead_category_scan enable row level security;
revoke all on public.lead_category_scan from anon, authenticated;

create or replace function public.fn_category_classify(p_text text)
returns table(slug text, score int, evidence text)
language sql
stable
set search_path = public, pg_temp
as $$
  with hay as (select ' ' || lower(regexp_replace(coalesce(p_text,''), '[^[:alnum:]]+', ' ', 'g')) || ' ' as h),
  hit as (
    select k.slug, k.weight, k.negative, k.pattern,
           btrim(lower(regexp_replace(k.pattern, '[^[:alnum:]]+', ' ', 'g'))) as pat
      from category_keyword k, hay
     where hay.h like '%' || btrim(lower(regexp_replace(k.pattern, '[^[:alnum:]]+', ' ', 'g'))) || '%'
  )
  select h.slug,
         sum(case when h.negative then -h.weight else h.weight end)::int as score,
         string_agg(h.pattern, '; ' order by h.weight desc, h.pattern) filter (where not h.negative) as evidence
    from hit h, hay
   where h.pat <> '' and hay.h ~ ('\m' || h.pat || '\M')
   group by h.slug
  having sum(case when h.negative then -h.weight else h.weight end) >= 3
$$;

create or replace function public.fn_supplier_discovery_promote(p_limit int default 300, p_classify int default 500)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_run bigint; v_cand int := 0; v_ins int := 0; v_dup int := 0; v_cat int := 0;
  v_scanned int := 0; v_scanned_matched int := 0; v_staged_left int := 0;
  v_n int; v_id bigint; v_txt text; r record;
begin
  insert into scrape_runs (run_id, dataset_id, actor, sector, emirate, label, status, requested)
  values ('staged-' || to_char(now() at time zone 'UTC', 'YYYYMMDD-HH24MISS'), 'yello_staging',
          'yello_staging:promote', 'mixed', 'UAE', 'staged directory promotion ' || current_date, 'RUNNING', p_limit)
  returning id into v_run;

  -- 4. duplicates first, so the pick below never considers them again. An existing lead with the
  --    same email, the same company name or the same phone is the same supplier.
  --    Measured 3 Sep 2026 before the first run: every one of the 11,152 staged rows with an email
  --    was already a lead by that email (the June directory import), and 135 of the 1,971 without
  --    one were already leads by name or phone. The staged source's remaining discovery is the
  --    ~1,840 email-less rows: real UAE suppliers, promoted with phone/website only, not sendable
  --    until an email is found for them.
  update yello_staging s
     set stage = 'duplicate',
         note  = 'a lead already carries this supplier (email, name or phone) — fn_supplier_discovery_promote ' || current_date
   where s.stage not in ('promoted', 'duplicate')
     and ((s.email is not null and s.email <> ''
           and exists (select 1 from leads l where l.email is not null and l.email <> '' and lower(l.email) = lower(s.email)))
       or exists (select 1 from leads l where lower(l.company_name) = lower(s.name))
       or (s.phone is not null and exists (select 1 from leads l where l.phone_e164 = s.phone or l.phone = s.phone)));
  get diagnostics v_dup = row_count;

  -- 2. the pick. The source category is scored against the catalogue once per distinct value (64),
  --    not once per row (13,123); the category's sendable pool decides the order, and a row that
  --    carries an email goes before one that does not.
  drop table if exists tmp_src;
  create temp table tmp_src on commit drop as
  select d.src_category, b.slug, coalesce(g.sendable, 0) as sendable
    from (select distinct src_category from yello_staging where src_category is not null) d
    left join lateral (select c.slug from public.fn_category_classify(replace(d.src_category, '-', ' ')) c
                        order by c.score desc, c.slug limit 1) b on true
    left join v_supply_gap g on g.slug = b.slug;

  drop table if exists tmp_pick;
  create temp table tmp_pick on commit drop as
  select s.company_id, s.name,
         case when s.email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then lower(s.email) end as email,
         s.phone, s.website, s.city, s.sector, s.src_category, s.categories, s.created_at, t.slug as src_slug
    from (select distinct on (coalesce(nullif(lower(s.email), ''), 'id:' || s.company_id)) s.*
            from yello_staging s
           where s.stage not in ('promoted', 'duplicate') and nullif(btrim(s.name), '') is not null
           order by coalesce(nullif(lower(s.email), ''), 'id:' || s.company_id), s.created_at) s
    left join tmp_src t on t.src_category = s.src_category
   order by (s.email is null or s.email = ''), coalesce(t.sendable, 0) asc, s.created_at
   limit greatest(coalesce(p_limit, 300), 0);
  select count(*) into v_cand from tmp_pick;

  -- 3. the leads, one at a time (at most p_limit), each classified as it lands. A row-by-row loop
  --    is chosen over a set insert because the staged row has to be marked with the lead it became
  --    and an email-less row has no key to join back on.
  for r in select * from tmp_pick loop
    v_txt := r.name || ' ' || coalesce(array_to_string(r.categories, ' '), '') || ' '
             || coalesce(r.sector, '') || ' ' || replace(coalesce(r.src_category, ''), '-', ' ');
    v_id := null;
    insert into leads (company_name, email, email_domain, phone, phone_e164, website, domain, city, emirate,
                       sector, categories, source, enrich_source, scraped_at, notes, invite_trades, created_at)
    values (r.name, r.email, split_part(r.email, '@', 2), r.phone,
            case when r.phone ~ '^\+[0-9]{8,15}$' then r.phone end,
            r.website,
            nullif(regexp_replace(lower(coalesce(r.website, '')), '^https?://(www\.)?([^/]+).*$', '\2'), ''),
            r.city, nullif(public.fn_norm_emirate(r.city), 'unknown'),
            r.sector, nullif(array_to_string(r.categories, ', '), ''),
            'yello_staging', 'directory', r.created_at::date,
            'promoted from yello_staging ' || r.company_id || ' (' || coalesce(r.src_category, '?') || ') by fn_supplier_discovery_promote on ' || current_date,
            public.fn_norm_trades(v_txt), now())
    on conflict do nothing
    returning id into v_id;
    if v_id is null then
      update yello_staging set stage = 'duplicate',
             note = 'a lead already carries this supplier (unique key) — fn_supplier_discovery_promote ' || current_date
       where company_id = r.company_id;
      v_dup := v_dup + 1;
      continue;
    end if;
    v_ins := v_ins + 1;
    insert into lead_category (lead_id, slug, score, is_primary, method, evidence)
    select v_id, c.slug, c.score, row_number() over (order by c.score desc, c.slug) = 1, 'keyword_v1', left(c.evidence, 400)
      from public.fn_category_classify(v_txt) c
    on conflict do nothing;
    get diagnostics v_n = row_count;
    -- The directory's own category is evidence too. Measured on the first 300: the lexicon placed 5
    -- of them from name + sector alone, so when it places none the directory heading decides.
    if v_n = 0 and r.src_slug is not null then
      insert into lead_category (lead_id, slug, score, is_primary, method, evidence)
      values (v_id, r.src_slug, 3, true, 'keyword_v1', 'directory category: ' || r.src_category)
      on conflict do nothing;
      get diagnostics v_n = row_count;
    end if;
    v_cat := v_cat + v_n;
    insert into lead_category_scan (lead_id, matched) values (v_id, v_n) on conflict do nothing;
    update yello_staging set stage = 'promoted',
           note = 'promoted to leads #' || v_id || ' by fn_supplier_discovery_promote on ' || current_date
     where company_id = r.company_id;
  end loop;

  -- 5. leads the lexicon has never been run over, approved suppliers first.
  drop table if exists tmp_scan;
  create temp table tmp_scan on commit drop as
  select l.id, l.company_name || ' ' || coalesce(l.categories, '') || ' ' || coalesce(l.sector, '') || ' '
         || coalesce(l.services, '') || ' ' || coalesce(l.products, '') || ' ' || coalesce(l.description, '') as txt
    from leads l
   where (l.approval_status = 'approved' or (l.email is not null and l.email <> '' and coalesce(l.banned, false) = false))
     and not exists (select 1 from lead_category c where c.lead_id = l.id)
     and not exists (select 1 from lead_category_scan x where x.lead_id = l.id)
   -- coalesce, not a bare comparison: 20,464 of 20,465 leads have a NULL approval_status, and NULL
   -- sorts FIRST under DESC, which put the one approved supplier behind all of them (measured).
   order by coalesce(l.approval_status = 'approved', false) desc, l.id
   limit greatest(coalesce(p_classify, 500), 0);
  select count(*) into v_scanned from tmp_scan;

  insert into lead_category (lead_id, slug, score, is_primary, method, evidence)
  select z.id, z.slug, z.score, z.rn = 1, 'keyword_v1', left(z.evidence, 400)
    from (select t.id, c.slug, c.score, c.evidence,
                 row_number() over (partition by t.id order by c.score desc, c.slug) rn
            from tmp_scan t cross join lateral public.fn_category_classify(t.txt) c) z
  on conflict do nothing;
  insert into lead_category_scan (lead_id, matched)
  select t.id, (select count(*) from lead_category c where c.lead_id = t.id) from tmp_scan t
  on conflict do nothing;
  select count(*) into v_scanned_matched from tmp_scan t where exists (select 1 from lead_category c where c.lead_id = t.id);

  select count(*) into v_staged_left from yello_staging where stage not in ('promoted', 'duplicate');

  update scrape_runs set status = 'COLLECTED', fetched = v_cand, inserted = v_ins, collected_at = now() where id = v_run;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('supplier_discovery', now(), now(), 'ok',
          jsonb_build_object('scrape_run_id', v_run, 'candidates', v_cand, 'promoted', v_ins, 'categorised', v_cat,
                             'duplicates_marked', v_dup, 'existing_scanned', v_scanned,
                             'existing_matched', v_scanned_matched, 'staged_left', v_staged_left),
          'Supplier discovery: ' || v_ins || ' staged directory row(s) promoted to leads (' || v_cat
          || ' category assignment(s)), ' || v_dup || ' marked duplicate, ' || v_scanned
          || ' existing lead(s) classified (' || v_scanned_matched || ' matched); '
          || v_staged_left || ' staged row(s) still to promote.');

  return jsonb_build_object('scrape_run_id', v_run, 'candidates', v_cand, 'promoted', v_ins, 'categorised', v_cat,
                            'duplicates_marked', v_dup, 'existing_scanned', v_scanned,
                            'existing_matched', v_scanned_matched, 'staged_left', v_staged_left);
end $function$;

-- SECURITY DEFINER routines are created with EXECUTE granted to PUBLIC; the promoter writes leads.
revoke execute on function public.fn_supplier_discovery_promote(int, int) from public, anon, authenticated;
