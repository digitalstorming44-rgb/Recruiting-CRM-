begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('crm-documents','crm-documents',false,15728640,array['application/pdf','image/jpeg','image/png']) on conflict(id) do nothing;
-- Object names are <lead ID>/<unique filename>. Existing lead RLS scopes each lookup.
create policy crm_documents_read on storage.objects for select to authenticated using(bucket_id='crm-documents' and (select private.crm_session_ok()) and exists(select 1 from public.oo_leads l where l.id::text=split_part(name,'/',1)));
create policy crm_documents_insert on storage.objects for insert to authenticated with check(bucket_id='crm-documents' and (select private.crm_session_ok()) and exists(select 1 from public.oo_leads l where l.id::text=split_part(name,'/',1)));
create policy crm_documents_update on storage.objects for update to authenticated using(bucket_id='crm-documents' and (select private.crm_session_ok()) and exists(select 1 from public.oo_leads l where l.id::text=split_part(name,'/',1))) with check(bucket_id='crm-documents' and (select private.crm_session_ok()) and exists(select 1 from public.oo_leads l where l.id::text=split_part(name,'/',1)));
create policy crm_documents_delete on storage.objects for delete to authenticated using(bucket_id='crm-documents' and (select private.crm_session_ok()) and exists(select 1 from public.oo_leads l where l.id::text=split_part(name,'/',1)));
commit;
