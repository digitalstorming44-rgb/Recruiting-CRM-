begin;
create or replace function private.crm_capture_permission_ddl() returns event_trigger language plpgsql security definer set search_path='' as $$
declare command record;
begin
 for command in select * from pg_event_trigger_ddl_commands() loop
   if command.command_tag in ('CREATE POLICY','ALTER POLICY','GRANT','REVOKE','ALTER TABLE') and (command.schema_name in ('public','storage','private') or command.schema_name is null) then
     insert into private.crm_audit(actor_id,actor_name,action,event_type,target,new_value)
     values(auth.uid(),coalesce((select full_name from public.profiles where id=auth.uid()),session_user),'Database permission / configuration changed','permissions',command.object_identity,jsonb_build_object('command',command.command_tag));
   end if;
 end loop;
end;$$;
revoke all on function private.crm_capture_permission_ddl() from public,anon,authenticated;
create event trigger crm_permission_ddl on ddl_command_end execute function private.crm_capture_permission_ddl();
create or replace function private.crm_capture_permission_drop() returns event_trigger language plpgsql security definer set search_path='' as $$
declare object record;
begin
 for object in select * from pg_event_trigger_dropped_objects() loop
   if object.object_type='policy' then
     insert into private.crm_audit(actor_id,actor_name,action,event_type,target,new_value) values(auth.uid(),session_user,'Database policy removed','permissions',object.object_identity,jsonb_build_object('command',tg_tag));
   end if;
 end loop;
end;$$;
revoke all on function private.crm_capture_permission_drop() from public,anon,authenticated;
create event trigger crm_permission_drop on sql_drop execute function private.crm_capture_permission_drop();
commit;
