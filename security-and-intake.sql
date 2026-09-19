-- Additive upgrade. Existing leads and account data are preserved.
begin;
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

alter table public.oo_leads add column if not exists recruiting_details jsonb not null default '{}'::jsonb;
alter table public.oo_leads add column if not exists vin text;
alter table public.oo_leads alter column city drop not null;
alter table public.oo_leads alter column state drop not null;
alter table public.oo_leads alter column lead_source drop not null;
alter table public.oo_leads alter column truck_type drop not null;
alter table public.oo_leads alter column authority_status drop not null;
alter table public.oo_leads alter column ownership_type drop not null;
alter table public.oo_leads alter column ownership_type drop default;
create index if not exists oo_leads_vin_normalized_idx on public.oo_leads (upper(vin)) where vin is not null;
create index if not exists oo_leads_name_normalized_idx on public.oo_leads (lower(full_name));
create index if not exists oo_leads_company_normalized_idx on public.oo_leads (lower(company_name));

create table if not exists private.crm_audit (
 id bigint generated always as identity primary key,
 actor_id uuid, actor_name text not null default 'System / database',
 action text not null, event_type text not null, target text,
 previous_value jsonb, new_value jsonb, created_at timestamptz not null default now()
);
alter table private.crm_audit enable row level security;
revoke all on private.crm_audit from public,anon,authenticated;
create index if not exists crm_audit_time_idx on private.crm_audit(created_at desc,id desc);
create index if not exists crm_audit_actor_time_idx on private.crm_audit(actor_id,created_at desc);

create or replace function private.crm_session_ok() returns boolean language sql stable security definer set search_path='' as $$
 select (select auth.uid()) is not null and exists (
   select 1 from public.profiles p join auth.sessions s on s.user_id=p.id
   where p.id=(select auth.uid()) and p.active and p.deleted_at is null
   and s.id::text=(select auth.jwt()->>'session_id')
   and (s.not_after is null or s.not_after>now())
 );
$$;
revoke all on function private.crm_session_ok() from public,anon;
grant execute on function private.crm_session_ok() to authenticated;

create or replace function private.crm_require_admin() returns void language plpgsql stable security definer set search_path='' as $$
begin
 if not private.crm_session_ok() or not exists(select 1 from public.profiles where id=auth.uid() and role='admin') then
   raise exception 'Active Admin session required' using errcode='42501';
 end if;
end; $$;
revoke all on function private.crm_require_admin() from public,anon;
grant execute on function private.crm_require_admin() to authenticated;

-- Restrictive gates supplement existing ownership policies; they do not broaden access.
do $$ declare item record; begin
 for item in select tablename from pg_tables where schemaname='public' and tablename in ('profiles','oo_leads','oo_followups','oo_activities','oo_call_logs','oo_documents','oo_qualification_checks','oo_status_history','oo_duplicate_decisions','team_messages','notifications') loop
   execute format('alter table public.%I enable row level security',item.tablename);
   execute format('drop policy if exists crm_active_session on public.%I',item.tablename);
   execute format('create policy crm_active_session on public.%I as restrictive for all to authenticated using ((select private.crm_session_ok())) with check ((select private.crm_session_ok()))',item.tablename);
 end loop;
end $$;

create or replace function private.crm_capture_change() returns trigger language plpgsql security definer set search_path='' as $$
declare before_data jsonb; after_data jsonb; actor uuid:=auth.uid(); action_name text; old_diff jsonb:='{}'; new_diff jsonb:='{}'; field text;
begin
 before_data:=case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;
 after_data:=case when tg_op='DELETE' then '{}'::jsonb else to_jsonb(new) end;
 -- Never store authentication secrets; this trigger is only on CRM business tables.
 if tg_op='UPDATE' then
   for field in select jsonb_object_keys(after_data) loop
     if field not in ('updated_at') and before_data->field is distinct from after_data->field then
       old_diff:=old_diff||jsonb_build_object(field,before_data->field);
       new_diff:=new_diff||jsonb_build_object(field,after_data->field);
     end if;
   end loop;
   if new_diff='{}'::jsonb then return new; end if;
 else old_diff:=before_data;new_diff:=after_data;end if;
 action_name:=case when tg_op='DELETE' then 'Permanent delete' when tg_op='INSERT' then 'Created' else 'Updated' end;
 if tg_table_name='oo_leads' and tg_op='UPDATE' and before_data->>'archived_at' is distinct from after_data->>'archived_at' then action_name:=case when after_data->>'archived_at' is null then 'Restored' else 'Archived' end;end if;
 if tg_table_name='profiles' and tg_op='UPDATE' then
   if before_data->>'role' is distinct from after_data->>'role' then action_name:='Role / permission changed';
   elsif before_data->>'active' is distinct from after_data->>'active' then action_name:=case when (after_data->>'active')::boolean then 'Reactivated' else 'Suspended' end;end if;
 end if;
 insert into private.crm_audit(actor_id,actor_name,action,event_type,target,previous_value,new_value)
 values(actor,coalesce((select full_name from public.profiles where id=actor),'System / database'),action_name,case when tg_table_name='profiles' then 'user_security' else 'lead' end,tg_table_name||':'||coalesce(after_data->>'id',before_data->>'id'),old_diff,new_diff);
 return case when tg_op='DELETE' then old else new end;
end; $$;
revoke all on function private.crm_capture_change() from public,anon,authenticated;
drop trigger if exists crm_audit_leads on public.oo_leads;
create trigger crm_audit_leads after insert or update or delete on public.oo_leads for each row execute function private.crm_capture_change();
drop trigger if exists crm_audit_profiles on public.profiles;
create trigger crm_audit_profiles after insert or update or delete on public.profiles for each row execute function private.crm_capture_change();

-- Revoke access immediately when an administrator suspends an account.
create or replace function private.crm_suspend_sessions() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.active and not new.active then delete from auth.sessions where user_id=new.id; end if;
 return new;
end; $$;
revoke all on function private.crm_suspend_sessions() from public,anon,authenticated;
drop trigger if exists crm_suspend_sessions on public.profiles;
create trigger crm_suspend_sessions after update of active on public.profiles for each row execute function private.crm_suspend_sessions();

create or replace function private.crm_security_action(p_action text,p_target text,p_confirmation text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare target_id uuid; affected integer; lead_id bigint;
begin
 perform private.crm_require_admin();
 if p_action in ('suspend','reactivate','revoke_sessions') then
   target_id:=p_target::uuid;
   if target_id=auth.uid() then raise exception 'Use your own sign-out controls; this action cannot target yourself';end if;
   perform 1 from public.profiles where id=target_id for update;
   if not found then raise exception 'User not found';end if;
   if p_confirmation<>p_action||':'||p_target then raise exception 'Confirmation is required';end if;
   if p_action='suspend' then update public.profiles set active=false,updated_at=now() where id=target_id;
   elsif p_action='reactivate' then update public.profiles set active=true,deleted_at=null,updated_at=now() where id=target_id;
   else delete from auth.sessions where user_id=target_id;get diagnostics affected=row_count;
     insert into private.crm_audit(actor_id,actor_name,action,event_type,target,new_value) select auth.uid(),full_name,'Sessions revoked','user_security',p_target,jsonb_build_object('sessions_revoked',affected) from public.profiles where id=auth.uid();
   end if;
 elsif p_action='permanent_delete' then
   lead_id:=p_target::bigint;
   if p_confirmation<>'DELETE '||p_target then raise exception 'Type DELETE followed by the lead ID';end if;
   if not exists(select 1 from public.oo_leads where id=lead_id and archived_at is not null) then raise exception 'Archive the lead before permanent deletion';end if;
   delete from public.oo_leads where id=lead_id; -- audit trigger participates in the same transaction
 else raise exception 'Unsupported action';end if;
 return jsonb_build_object('ok',true);
end; $$;
revoke all on function private.crm_security_action(text,text,text) from public,anon;
grant execute on function private.crm_security_action(text,text,text) to authenticated;
create or replace function public.crm_security_action(p_action text,p_target text,p_confirmation text default '') returns jsonb language sql security invoker set search_path='' as $$ select private.crm_security_action(p_action,p_target,p_confirmation); $$;
revoke all on function public.crm_security_action(text,text,text) from public,anon;
grant execute on function public.crm_security_action(text,text,text) to authenticated;

create or replace function private.crm_security_snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
declare relations jsonb; people jsonb; buckets jsonb; all_rls boolean; logging_ok boolean;
begin
 perform private.crm_require_admin();
 select jsonb_agg(jsonb_build_object('table',c.relname,'rls',c.relrowsecurity,'policy_count',(select count(*) from pg_policy p where p.polrelid=c.oid),'session_gate',exists(select 1 from pg_policy p where p.polrelid=c.oid and p.polname='crm_active_session'))),bool_and(c.relrowsecurity and exists(select 1 from pg_policy p where p.polrelid=c.oid and p.polname='crm_active_session')) into relations,all_rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r';
 select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'role',p.role,'active',p.active,'deleted_at',p.deleted_at,'last_login',u.last_sign_in_at,'mfa_verified',exists(select 1 from auth.mfa_factors f where f.user_id=p.id and f.status='verified'),'sessions',(select count(*) from auth.sessions s where s.user_id=p.id and (s.not_after is null or s.not_after>now())))) into people from public.profiles p left join auth.users u on u.id=p.id;
 select jsonb_agg(jsonb_build_object('name',id,'public',public)) into buckets from storage.buckets;
 select count(*)=2 into logging_ok from pg_trigger where tgname in ('crm_audit_leads','crm_audit_profiles') and tgenabled<>'D';
 return jsonb_build_object('checked_at',now(),'database',jsonb_build_object('status',case when all_rls then 'Protected' else 'Attention Required' end,'detail','RLS and active-session gates checked. This is a configuration check, not a complete security certification.','tables',relations),'storage',jsonb_build_object('status',case when not exists(select 1 from storage.buckets where id='crm-documents') then 'Not Configured' when exists(select 1 from storage.buckets where id='crm-documents' and not public) and (select count(*) from pg_policies where schemaname='storage' and tablename='objects' and policyname in ('crm_documents_read','crm_documents_insert','crm_documents_update','crm_documents_delete'))=4 and not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and permissive='PERMISSIVE' and policyname not in ('crm_documents_read','crm_documents_insert','crm_documents_update','crm_documents_delete')) then 'Protected' else 'Attention Required' end,'detail','CRM document bucket is private with active-session and lead-access policies. Paths use lead ID / filename.','buckets',coalesce(buckets,'[]'::jsonb)),'audit',jsonb_build_object('status',case when logging_ok then 'Protected' else 'Attention Required' end,'detail','Database triggers capture lead and user changes; Supabase Auth events are queried separately. History begins when logging was installed.'),'mfa',jsonb_build_object('status',case when not exists(select 1 from auth.mfa_factors f join public.profiles p on p.id=f.user_id where f.status='verified' and p.active and p.role in ('admin','manager')) then 'Not Configured' else 'Attention Required' end,'detail','User enrollment is shown below. Mandatory MFA enforcement is not enabled by this upgrade; enrollment alone is not marked Protected.'),'users',coalesce(people,'[]'::jsonb));
end; $$;
revoke all on function private.crm_security_snapshot() from public,anon;
grant execute on function private.crm_security_snapshot() to authenticated;
create or replace function public.crm_security_snapshot() returns jsonb language sql security invoker set search_path='' as $$select private.crm_security_snapshot();$$;
revoke all on function public.crm_security_snapshot() from public,anon;
grant execute on function public.crm_security_snapshot() to authenticated;

create or replace function private.crm_audit_page(p_user text default '',p_action text default '',p_type text default '',p_from timestamptz default null,p_to timestamptz default null,p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform private.crm_require_admin();
 select coalesce(jsonb_agg(to_jsonb(entries)),'[]'::jsonb) into result from (
   select * from (
     select id::text,actor_id::text,actor_name,action,event_type,target,previous_value,new_value,created_at from private.crm_audit
     union all
     select a.id::text,a.payload->>'actor_id',coalesce(p.full_name,'Auth service'),coalesce(a.payload->>'action','Authentication event'),'authentication',coalesce(a.payload->>'actor_id',''),null::jsonb,jsonb_build_object('provider',a.payload->'traits'->>'provider'),a.created_at from auth.audit_log_entries a left join public.profiles p on p.id::text=a.payload->>'actor_id'
   ) combined where (p_user='' or actor_id=p_user) and (p_action='' or action ilike '%'||p_action||'%') and (p_type='' or event_type=p_type) and (p_from is null or created_at>=p_from) and (p_to is null or created_at<p_to)
   order by created_at desc,id desc limit 51 offset greatest(0,least(p_offset,100000))
 ) entries;
 return result;
end; $$;
revoke all on function private.crm_audit_page(text,text,text,timestamptz,timestamptz,integer) from public,anon;
grant execute on function private.crm_audit_page(text,text,text,timestamptz,timestamptz,integer) to authenticated;
create or replace function public.crm_audit_page(p_user text default '',p_action text default '',p_type text default '',p_from timestamptz default null,p_to timestamptz default null,p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.crm_audit_page(p_user,p_action,p_type,p_from,p_to,p_offset);$$;
revoke all on function public.crm_audit_page(text,text,text,timestamptz,timestamptz,integer) from public,anon;
grant execute on function public.crm_audit_page(text,text,text,timestamptz,timestamptz,integer) to authenticated;

-- A narrowly scoped access check for the existing server-side administration endpoint.
create or replace function public.crm_admin_context() returns boolean language plpgsql security invoker set search_path='' as $$begin perform private.crm_require_admin();return true;end;$$;
revoke all on function public.crm_admin_context() from public,anon;
grant execute on function public.crm_admin_context() to authenticated;
commit;
