-- A CUSTOMER RATING NOTIFIES THE SALES ENGINEER
--
-- The founder, 9 September 2026, following on from the voluntary star rating in the customer
-- portal: "once that is done, the sales engineer should directly get notified to include it in
-- the database."
--
-- WHY A TRIGGER AND NOT A LINE IN customer_api. Sales owns supplier truth — Sales decides and
-- writes the technical record, Support carries messages — and there is more than one way a
-- reviews row can appear: CustomerPortal.tsx:1338 -> customer_api `rate_supplier` today, and the
-- 21-day solicitation fn_support_request_ratings_due leads a customer back to the same portal
-- button tomorrow. Both converge on the SAME reviews row, so the notification is keyed on the
-- ROW, at the table, where every writer passes. A notify bolted to one caller is a notify the
-- other caller does not have.
--
-- THE KEY IS THE TRANSACTION, NOT THE PATH. public.reviews carries UNIQUE (transaction_id) and
-- customer_api upserts on it, so a customer who changes their mind produces an UPDATE, not a
-- second review — and this must produce an UPDATE, not a second task.
--
-- THE LOOKUP IS UNFILTERED BY STATUS, DELIBERATELY. fn_agent_action_work_sweep guards its unique
-- key with a status filter, so a previously FAILED row occupies the key without satisfying the
-- guard and the retry opens a '#2' — the scar that caps every attempt at two. Keyed here on the
-- transaction alone, a failed or cancelled task is FOUND and reopened rather than duplicated.
--
-- IT CAN NEVER BLOCK THE RATING. The whole body is inside an exception handler that returns the
-- row unchanged. If org_tasks refuses the write for any reason the rating is still saved and
-- customer_api still answers ok:true — a customer must never lose their rating because an internal
-- task queue had an opinion.
--
-- NO MODEL. Nothing here needs judgement: it is a row appearing, an owner, and a durable note.

create or replace function public.fn_sales_rating_landed()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_task     bigint;
  v_company  text;
  v_customer text;
  v_title    text;
  v_payload  jsonb;
begin
  select l.company_name into v_company from public.leads l where l.id = new.supplier_id;
  select coalesce(nullif(btrim(c.full_name), ''), c.email) into v_customer
    from public.customers c where c.id = new.customer_id;

  v_title := left('Customer rating landed: ' || coalesce(v_company, 'supplier #' || new.supplier_id)
             || ' — ' || new.rating || '/5', 200);

  v_payload := jsonb_build_object(
    'transaction_id', new.transaction_id,
    'review_id',      new.id,
    'supplier_id',    new.supplier_id,
    'supplier',       v_company,
    'customer_id',    new.customer_id,
    'customer',       v_customer,
    'inquiry_id',     new.inquiry_id,
    'rating',         new.rating,
    'comment',        left(coalesce(new.comment, ''), 500),
    'arrived_at',     now(),
    'op',             tg_op);

  -- UNFILTERED BY STATUS. Every task this transaction has ever opened, in any state.
  select t.id into v_task
    from public.org_tasks t
   where t.result -> 'sales_rating' ->> 'transaction_id' = new.transaction_id::text
   order by t.id desc
   limit 1;

  if v_task is not null then
    update public.org_tasks
       set result = jsonb_set(coalesce(result, '{}'::jsonb), '{sales_rating}',
                      coalesce(result -> 'sales_rating', '{}'::jsonb) || v_payload
                      || jsonb_build_object('revisions',
                           coalesce((result -> 'sales_rating' ->> 'revisions')::int, 1) + 1)),
           title      = v_title,
           updated_at = now()
     where id = v_task;
  else
    insert into public.org_tasks (title, detail, status, tier, needs_founder, decided_by,
                                  action_class, assigned_agent, priority, result)
    values (v_title,
            'A QuotesDone customer rated a supplier they paid to reveal and actually dealt with.'
              || E'\n\nSupplier: ' || coalesce(v_company, 'id ' || new.supplier_id)
              || E'\nCustomer: ' || coalesce(v_customer, 'id ' || new.customer_id)
              || E'\nTransaction: ' || new.transaction_id
              || coalesce(E'\nInquiry: ' || new.inquiry_id::text, '')
              || E'\nRating: ' || new.rating || '/5'
              || coalesce(E'\nComment: ' || nullif(btrim(new.comment), ''), '')
              || E'\n\nIncorporate it into the supplier record: recompute_supplier_rating() has'
              || ' already run on the aggregate, so what is left is the judgement this seat owns —'
              || ' whether this rating changes the supplier''s standing, their declared capability,'
              || ' or their eligibility for the trades they are matched on. If the customer changes'
              || ' their rating this task is updated, never duplicated.',
            'assigned', 'advisory', false, 'fn_sales_rating_landed',
            'routine_operational_decision', 'sales_engineer', 1,
            jsonb_build_object('sales_rating', v_payload || jsonb_build_object('revisions', 1)))
    returning id into v_task;
  end if;

  return new;
exception when others then
  -- THE RATING WINS. Always.
  return new;
end
$function$;

revoke execute on function public.fn_sales_rating_landed() from public;

drop trigger if exists t60_sales_rating_landed on public.reviews;
create trigger t60_sales_rating_landed
  after insert or update on public.reviews
  for each row execute function public.fn_sales_rating_landed();
