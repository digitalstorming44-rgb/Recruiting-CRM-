begin;
create or replace function private.crm_record_admin_request(p_actor uuid,p_action text,p_target text) returns void language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' or not exists(select 1 from public.profiles where id=p_actor and role='admin' and active and deleted_at is null) then raise exception 'Server-side Admin authorization required' using errcode='42501';end if;
 if p_action not in ('create','reset_password','set_active','update_role','remove_access') then raise exception 'Unsupported Admin action';end if;
 insert into private.crm_audit(actor_id,actor_name,action,event_type,target,new_value) select p_actor,full_name,'Admin request: '||p_action,'admin',left(p_target,100),jsonb_build_object('phase','requested','note','Request recorded before execution; resulting profile changes and Auth events show the outcome.') from public.profiles where id=p_actor;
end;$$;
revoke all on function private.crm_record_admin_request(uuid,text,text) from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.crm_record_admin_request(uuid,text,text) to service_role;
create or replace function public.crm_record_admin_request(p_actor uuid,p_action text,p_target text) returns void language sql security invoker set search_path='' as $$select private.crm_record_admin_request(p_actor,p_action,p_target);$$;
revoke all on function public.crm_record_admin_request(uuid,text,text) from public,anon,authenticated;
grant execute on function public.crm_record_admin_request(uuid,text,text) to service_role;
commit;
