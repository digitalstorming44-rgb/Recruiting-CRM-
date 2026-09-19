begin;
create table if not exists private.crm_ai_usage(user_id uuid not null references public.profiles(id) on delete cascade,window_start timestamptz not null,requests integer not null default 1,primary key(user_id,window_start));
alter table private.crm_ai_usage enable row level security;
revoke all on private.crm_ai_usage from public,anon,authenticated;
create or replace function private.crm_allow_ai_intake() returns boolean language plpgsql security definer set search_path='' as $$
declare total integer;
begin
 if not private.crm_session_ok() then raise exception 'Active session required' using errcode='42501';end if;
 insert into private.crm_ai_usage(user_id,window_start) values(auth.uid(),date_trunc('hour',now())) on conflict(user_id,window_start) do update set requests=private.crm_ai_usage.requests+1 where private.crm_ai_usage.requests<20 returning requests into total;
 return total is not null;
end;$$;
revoke all on function private.crm_allow_ai_intake() from public,anon;
grant execute on function private.crm_allow_ai_intake() to authenticated;
create or replace function public.crm_allow_ai_intake() returns boolean language sql security invoker set search_path='' as $$select private.crm_allow_ai_intake();$$;
revoke all on function public.crm_allow_ai_intake() from public,anon;
grant execute on function public.crm_allow_ai_intake() to authenticated;
commit;
