begin;
create or replace function public.crm_find_duplicates(p_candidate jsonb) returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) from (
 select l.*, array_remove(array[
   case when nullif(regexp_replace(p_candidate->>'phone','[^0-9]','','g'),'') is not null and right(regexp_replace(l.phone,'[^0-9]','','g'),10)=right(regexp_replace(p_candidate->>'phone','[^0-9]','','g'),10) then 'Phone' end,
   case when nullif(p_candidate->>'email','') is not null and lower(trim(l.email))=lower(trim(p_candidate->>'email')) then 'Email' end,
   case when nullif(p_candidate->>'dot_number','') is not null and l.dot_number=p_candidate->>'dot_number' then 'DOT Number' end,
   case when nullif(p_candidate->>'mc_number','') is not null and l.mc_number=p_candidate->>'mc_number' then 'MC Number' end,
   case when nullif(p_candidate->>'vin','') is not null and upper(l.vin)=upper(p_candidate->>'vin') then 'VIN' end,
   case when nullif(p_candidate->>'company','') is not null and regexp_replace(lower(l.company_name),'[^a-z0-9]','','g')=regexp_replace(lower(p_candidate->>'company'),'[^a-z0-9]','','g') then 'Company' end,
   case when nullif(p_candidate->>'name','') is not null and regexp_replace(lower(l.full_name),'[^a-z0-9]','','g')=regexp_replace(lower(p_candidate->>'name'),'[^a-z0-9]','','g') then 'Applicant Name' end,
   case when nullif(p_candidate->>'secondary_phone','') is not null and right(regexp_replace(p_candidate->>'secondary_phone','[^0-9]','','g'),10) in (right(regexp_replace(l.phone,'[^0-9]','','g'),10),right(regexp_replace(l.secondary_phone,'[^0-9]','','g'),10)) then 'Secondary Phone' end,
   case when nullif(p_candidate->>'phone','') is not null and right(regexp_replace(p_candidate->>'phone','[^0-9]','','g'),10)=right(regexp_replace(l.secondary_phone,'[^0-9]','','g'),10) then 'Secondary Phone' end
 ],null) reasons
 from public.oo_leads l
 ) m where cardinality(m.reasons)>0;
$$;
revoke all on function public.crm_find_duplicates(jsonb) from public,anon;
grant execute on function public.crm_find_duplicates(jsonb) to authenticated;

create or replace function public.crm_merge_intake(p_lead_id bigint,p_expected_updated_at timestamptz,p_fields jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare current_record public.oo_leads; key text;
begin
 if not private.crm_session_ok() then raise exception 'Active session required' using errcode='42501';end if;
 if jsonb_typeof(p_fields)<>'object' or length(p_fields::text)>60000 then raise exception 'Invalid reviewed fields';end if;
 for key in select jsonb_object_keys(p_fields) loop
   if key<>all(array['name','company','phone','secondary_phone','email','source','full_address','street_address','city','state','zip_code','dot_number','mc_number','applied_under_authority','intended_authority','authority','truck','vehicle_length','vin','ownership','liftgate','pallet_jack','equipment_notes','insurance_type','auto_liability','cargo_coverage','preferred_loads','road_availability','driving_experience','otr_experience','driver_type','eld','start_availability','weekly_income_goal','percentage_split','pipeline_status','priority','notes']) then raise exception 'Unsupported field';end if;
   if jsonb_typeof(p_fields->key)<>'string' then raise exception 'Field values must be text';end if;
 end loop;
 if p_fields?'name' and trim(p_fields->>'name')='' then raise exception 'Name is required';end if;
 if p_fields?'phone' and (p_fields->>'phone') !~ '^\+?[0-9 ()-]{8,22}$' then raise exception 'Check phone';end if;
 if p_fields?'vin' and (p_fields->>'vin') !~ '^[A-HJ-NPR-Z0-9]{17}$' then raise exception 'Check VIN';end if;
 select * into current_record from public.oo_leads where id=p_lead_id for update;
 if not found then raise exception 'Lead unavailable or access denied';end if;
 if current_record.updated_at is distinct from p_expected_updated_at then raise exception 'This lead changed since your review. Reload and review again.';end if;
 update public.oo_leads set
 full_name=case when p_fields?'name' then p_fields->>'name' else full_name end,
 company_name=case when p_fields?'company' then p_fields->>'company' else company_name end,
 phone=case when p_fields?'phone' then p_fields->>'phone' else phone end,
 secondary_phone=case when p_fields?'secondary_phone' then p_fields->>'secondary_phone' else secondary_phone end,
 email=case when p_fields?'email' then p_fields->>'email' else email end,
 city=case when p_fields?'city' then p_fields->>'city' else city end,
 state=case when p_fields?'state' then p_fields->>'state' else state end,
 lead_source=case when p_fields?'source' then p_fields->>'source' else lead_source end,
 applied_under_authority=case when p_fields?'applied_under_authority' then p_fields->>'applied_under_authority' else applied_under_authority end,
 truck_type=case when p_fields?'truck' then p_fields->>'truck' else truck_type end,
 authority_status=case when p_fields?'authority' then p_fields->>'authority' else authority_status end,
 recruiter_notes=case when p_fields?'notes' then p_fields->>'notes' else recruiter_notes end,
 dot_number=case when p_fields?'dot_number' then p_fields->>'dot_number' else dot_number end,
 mc_number=case when p_fields?'mc_number' then p_fields->>'mc_number' else mc_number end,
 vin=case when p_fields?'vin' then p_fields->>'vin' else vin end,
 pipeline_status=case when p_fields?'pipeline_status' then p_fields->>'pipeline_status' else pipeline_status end,
 priority=case when p_fields?'priority' then (p_fields->>'priority')::public.lead_priority else priority end,
 recruiting_details=recruiting_details||p_fields||jsonb_build_object('_last_merge',jsonb_build_object('actor',auth.uid(),'at',now(),'fields',p_fields)),updated_at=clock_timestamp()
 where id=p_lead_id;
 if not found then raise exception 'Lead update denied';end if;
 return jsonb_build_object('ok',true,'id',p_lead_id);
end; $$;
revoke all on function public.crm_merge_intake(bigint,timestamptz,jsonb) from public,anon;
grant execute on function public.crm_merge_intake(bigint,timestamptz,jsonb) to authenticated;

-- Timestamp every update for optimistic merge conflict checks.
create or replace function private.crm_touch_lead() returns trigger language plpgsql set search_path='' as $$begin new.updated_at=clock_timestamp();return new;end;$$;
revoke all on function private.crm_touch_lead() from public,anon,authenticated;
drop trigger if exists crm_touch_lead on public.oo_leads;
create trigger crm_touch_lead before update on public.oo_leads for each row execute function private.crm_touch_lead();
commit;
