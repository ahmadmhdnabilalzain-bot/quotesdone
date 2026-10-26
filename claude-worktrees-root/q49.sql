select (select count(distinct (src,row_id)) from knowledge_vector_ml) rows_ml, fn_ml_read_space() space;
