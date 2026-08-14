-- THE INTELLIGENCE CENTRE COULD NOT SEE A CUSTOMER
--
-- Row #3 asks the Intelligence Center to show nine things on one screen. Eight of them reach it.
-- Customer behaviour does not: measured on production, no rendered component in the OS shell names
-- customer_health, customer_score, customer_ltv, customer_preference or churn — 0 of 79 components.
--
-- The data is there and is real. public.customer_health is a view over the live customer book and
-- carries engagement, satisfaction, progress, service, a health score and a risk tier per customer.
-- What was missing was a route from it to the screen: fn_ws_customers names the view but returns
-- only identity columns (id, email, phone, verified flags, counts), so nothing about how a customer
-- BEHAVES ever left the database.
--
-- WHY A NEW FUNCTION RATHER THAN A KEY ON fn_ws_intelligence. That routine is 6,939 characters of
-- CTEs and the only safe way to add a key is to reproduce the whole definition. Reconstructing a
-- large routine to add one clause is how a 13,455-character sweep nearly lost its STALLED
-- accounting on 14 Aug. A separate, small, single-purpose reader costs one os_api action and
-- carries no transcription risk.
--
-- TWO CUSTOMERS IS THE POPULATION, AND THE PAYLOAD SAYS SO. `customers` is returned beside the
-- aggregates so the screen can never present an average of two as though it were a trend. Averages
-- over an empty book are NULL, not 0 — a satisfaction of 0 would read as "customers are unhappy"
-- when the truth is that nobody has been asked.

create or replace function public.fn_ws_customer_behavior()
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_catalog'
as $function$
  select jsonb_build_object(
    'customers',        (select count(*) from customer_health),
    -- Averages over the real book. NULL when there is nobody to average, never 0.
    'avg_health',       (select round(avg(health)::numeric, 1)       from customer_health),
    'avg_engagement',   (select round(avg(engagement)::numeric, 1)   from customer_health),
    'avg_satisfaction', (select round(avg(satisfaction)::numeric, 1) from customer_health),
    'dormant',          (select count(*) from customer_health where coalesce(dormant, false)),
    'at_risk',          (select count(*) from customer_health where lower(coalesce(risk_tier,'')) in ('high','elevated','at_risk')),
    'with_rfqs',        (select count(*) from customer_health where coalesce(total_inq, 0) > 0),
    -- CHURN IS NOT MEASURED, AND SAYS SO RATHER THAN RETURNING A NUMBER. Every customer on this
    -- platform was created inside the last 30 days and none has completed a transaction, so there
    -- is no lapse to observe. A churn rate here would be arithmetic on an empty set.
    'churn_rate_pct',   null,
    'churn_note',       'Not measured: no customer is old enough to have lapsed and no transaction has completed, so there is nothing to compute a churn rate from.',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
              'customer_id', c.customer_id, 'name', c.full_name, 'email', c.email,
              'health', c.health, 'engagement', c.engagement, 'satisfaction', c.satisfaction,
              'progress', c.progress, 'service', c.service, 'risk_tier', c.risk_tier,
              'dormant', c.dormant, 'total_inq', c.total_inq, 'active_inq', c.active_inq,
              'stalled_inq', c.stalled_inq, 'last_activity', c.last_activity)
            order by c.health nulls last)
            from customer_health c), '[]'::jsonb),
    'generated_at', now()
  );
$function$;

-- Newly CREATEd SECURITY DEFINER functions are granted EXECUTE to PUBLIC; revoked in the same
-- migration. os_api reaches it with the service role.
revoke all on function public.fn_ws_customer_behavior() from public, anon, authenticated;

-- BOTH GATES IN THE SAME CHANGE. os_api classifies in its own ACTION_CLASS table and in
-- public.control_mode_action, and an action in one but not the other put a phone-code prompt in
-- front of eleven read-only screens on 14 Aug. requires_control is GENERATED and is not set here.
insert into public.control_mode_action (action, description, classification, risk)
values ('ws.customer_behavior',
        'Reads the customer_health view for the Intelligence Center. fn_ws_customer_behavior is STABLE and writes nothing.',
        'read_only', 'low')
on conflict (action) do update
  set classification = excluded.classification, description = excluded.description, risk = excluded.risk;
