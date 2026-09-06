CREATE OR REPLACE FUNCTION public.fn_rfq_score(i inquiries)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare pts int:=0; miss text[]:='{}'; have text[]:='{}'; spectxt text;
        catchk jsonb; catmiss text[]:='{}'; m jsonb; gready boolean; catok boolean;
begin
  spectxt := coalesce(i.spec::text,'');
  if coalesce(i.category,'')<>'' then pts:=pts+20; have:=array_append(have,'category'); else miss:=array_append(miss,'category'); end if;
  if coalesce(i.emirate,'')<>'' then pts:=pts+10; have:=array_append(have,'emirate'); else miss:=array_append(miss,'emirate'); end if;
  if length(regexp_replace(spectxt,'[^a-zA-Z0-9]','','g')) > 20 then pts:=pts+25; have:=array_append(have,'scope_detail'); else miss:=array_append(miss,'scope_detail'); end if;
  if coalesce(i.scope_type,'')<>'' then pts:=pts+15; have:=array_append(have,'scope_type'); else miss:=array_append(miss,'scope_type'); end if;
  if i.budget is not null then pts:=pts+15; have:=array_append(have,'budget'); else miss:=array_append(miss,'budget'); end if;
  if coalesce(array_length(i.trades,1),0)>0 or coalesce(i.drawing_file_path,'')<>'' or i.boq is not null then
     pts:=pts+15; have:=array_append(have,'supporting_detail'); else miss:=array_append(miss,'supporting_detail'); end if;

  gready := pts >= 70;

  catchk := public.fn_rfq_required_check(i);
  catok  := coalesce((catchk->>'required_ok')::boolean, true);

  if coalesce((catchk->>'applicable')::boolean,false) then
    for m in select value from jsonb_array_elements(coalesce(catchk->'missing','[]'::jsonb)) loop
      catmiss := array_append(catmiss, coalesce(nullif(m->>'question',''), m->>'key'));
    end loop;
  end if;

  return jsonb_build_object(
    'score', pts,
    'generic_ready', gready,
    'category_required_ok', catok,
    'ready', (gready and catok),
    'have', to_jsonb(have),
    'missing', to_jsonb(miss || catmiss),
    'category_missing', coalesce(catchk->'missing','[]'::jsonb),
    'category_check', catchk,
    'scored_at', now());
end $function$
