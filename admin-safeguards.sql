begin;
create or replace function private.crm_protect_last_admin() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.role='admin' and old.active and (new.role<>'admin' or not new.active) then
   perform pg_advisory_xact_lock(72491283);
   if not exists(select 1 from public.profiles where id<>old.id and role='admin' and active and deleted_at is null) then raise exception 'Keep at least one active Admin account';end if;
 end if;
 return new;
end;$$;
revoke all on function private.crm_protect_last_admin() from public,anon,authenticated;
drop trigger if exists crm_protect_last_admin on public.profiles;
create trigger crm_protect_last_admin before update of role,active on public.profiles for each row execute function private.crm_protect_last_admin();
commit;
