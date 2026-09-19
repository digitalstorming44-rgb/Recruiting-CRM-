-- Digital Storming CRM recruiting upgrade
-- Review before running. Designed for a Supabase project that already contains
-- public.profiles and public.oo_leads.

alter table public.profiles
  add column if not exists deleted_at timestamptz;

alter table public.oo_leads
  add column if not exists secondary_phone text,
  add column if not exists zip_code text,
  add column if not exists preferred_contact_method text,
  add column if not exists truck_year integer,
  add column if not exists truck_make text,
  add column if not exists truck_model text,
  add column if not exists truck_length text,
  add column if not exists has_liftgate boolean not null default false,
  add column if not exists has_pallet_jack boolean not null default false,
  add column if not exists capacity_lbs integer,
  add column if not exists equipment_notes text,
  add column if not exists own_authority boolean not null default false,
  add column if not exists company_authority text,
  add column if not exists dot_number text,
  add column if not exists mc_number text,
  add column if not exists pipeline_status text not null default 'New Lead',
  add column if not exists last_call_result text,
  add column if not exists recruiter_notes text,
  add column if not exists availability text,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references public.profiles(id);

create index if not exists oo_leads_phone_idx on public.oo_leads(phone);
create index if not exists oo_leads_email_lower_idx on public.oo_leads(lower(email));
create index if not exists oo_leads_recruiter_idx on public.oo_leads(assigned_recruiter_id);
create index if not exists oo_leads_pipeline_idx on public.oo_leads(pipeline_status);
create index if not exists oo_leads_qualification_idx on public.oo_leads(qualification_status);
create index if not exists oo_leads_followup_idx on public.oo_leads(next_follow_up_at);
create index if not exists oo_leads_created_idx on public.oo_leads(created_at);
create index if not exists oo_leads_dot_idx on public.oo_leads(dot_number);
create index if not exists oo_leads_mc_idx on public.oo_leads(mc_number);

create table if not exists public.oo_call_logs (
  id bigint generated always as identity primary key,
  lead_id bigint not null references public.oo_leads(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  result text not null,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.oo_documents (
  id bigint generated always as identity primary key,
  lead_id bigint not null references public.oo_leads(id) on delete cascade,
  document_type text not null,
  status text not null default 'Not Requested',
  storage_path text,
  notes text,
  expires_at date,
  uploaded_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.oo_qualification_checks (
  id bigint generated always as identity primary key,
  lead_id bigint not null references public.oo_leads(id) on delete cascade,
  check_key text not null,
  label text not null,
  completed boolean not null default false,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  notes text,
  unique (lead_id, check_key)
);

create table if not exists public.oo_status_history (
  id bigint generated always as identity primary key,
  lead_id bigint not null references public.oo_leads(id) on delete cascade,
  field_name text not null,
  old_value text,
  new_value text,
  changed_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.oo_duplicate_decisions (
  id bigint generated always as identity primary key,
  candidate_lead_id bigint references public.oo_leads(id) on delete set null,
  existing_lead_id bigint references public.oo_leads(id) on delete set null,
  decision text not null,
  reason text,
  decided_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.oo_call_logs enable row level security;
alter table public.oo_documents enable row level security;
alter table public.oo_qualification_checks enable row level security;
alter table public.oo_status_history enable row level security;
alter table public.oo_duplicate_decisions enable row level security;

-- Add project-specific RLS policies before granting browser access.
-- Policies must enforce assigned-recruiter, Manager and Admin permissions.
