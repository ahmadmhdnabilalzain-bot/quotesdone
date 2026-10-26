select jsonb_typeof(fn_company_state()->'departments') t, left((fn_company_state()->'departments')::text,120) v;
