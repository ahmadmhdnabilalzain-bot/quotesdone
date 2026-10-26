select to_jsonb(c)->>'calendar_sent_at' sent from  c where to_jsonb(c)::text like '%2026-month1-supplier-recruitment%';
