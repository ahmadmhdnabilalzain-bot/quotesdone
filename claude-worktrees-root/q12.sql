select public.fn_ml_read_space() space, (select count(distinct (src,row_id)) from knowledge_vector_ml) embedded_rows, (select count(*) from v_knowledge_ml_source) total_sources;
