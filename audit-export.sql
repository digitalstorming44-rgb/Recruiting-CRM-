begin;
create or replace function private.crm_export_audit_page(p_user text default '',p_action text default '',p_type text default '',p_from timestamptz default null,p_to timestamptz default null,p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform private.crm_require_admin();
 select coalesce(jsonb_agg(value),'[]'::jsonb) into result from (select value from jsonb_array_elements(private.crm_audit_page(p_user,p_action,p_type,p_from,p_to,p_offset)) limit 50) p;
 insert into private.crm_audit(actor_id,actor_name,action,event_type,target,new_value) select auth.uid(),full_name,'Audit export','admin','audit_log',jsonb_build_object('rows',jsonb_array_length(result),'filters',jsonb_build_object('user',p_user,'action',p_action,'type',p_type,'from',p_from,'to',p_to,'offset',p_offset)) from public.profiles where id=auth.uid();
 return result;
end; $$;
revoke all on function private.crm_export_audit_page(text,text,text,timestamptz,timestamptz,integer) from public,anon;
grant execute on function private.crm_export_audit_page(text,text,text,timestamptz,timestamptz,integer) to authenticated;
create or replace function public.crm_export_audit_page(p_user text default '',p_action text default '',p_type text default '',p_from timestamptz default null,p_to timestamptz default null,p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.crm_export_audit_page(p_user,p_action,p_type,p_from,p_to,p_offset);$$;
revoke all on function public.crm_export_audit_page(text,text,text,timestamptz,timestamptz,integer) from public,anon;
grant execute on function public.crm_export_audit_page(text,text,text,timestamptz,timestamptz,integer) to authenticated;
commit;
