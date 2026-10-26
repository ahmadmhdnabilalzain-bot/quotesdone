select relname, n_live_tup, pg_size_pretty(pg_total_relation_size(relid)) from pg_stat_user_tables where relname in ('pages','legal_documents','kb_chunks','agent_knowledge','deploy_state');
