-- AquaDesk Rebuild — Stage 1a: Schema + RLS
-- Target: the NEW, isolated Supabase project only. Never run against the live system.
-- Source of truth: aquadesk-rebuild-blueprint-v1.md, section 5 (Stage 1a).

-- =========================================================================
-- 0. Extensions
-- =========================================================================
create extension if not exists pgcrypto with schema extensions;

-- =========================================================================
-- 1. Enum types
-- =========================================================================
create type public.user_role as enum ('owner', 'secretary');
create type public.staff_position as enum ('secretary', 'divemaster', 'instructor', 'crew');
create type public.staff_employment_status as enum ('full_time', 'part_time', 'freelance');
create type public.certification_level as enum ('none', 'open_water_diver', 'advanced_open_water', 'rescue_diver', 'divemaster', 'instructor');
create type public.training_agency as enum ('padi', 'ssi', 'naui', 'cmas', 'other');
create type public.pricing_mode as enum ('tier', 'package');
create type public.subscription_status as enum ('trial', 'active', 'suspended', 'cancelled');
create type public.boat_type as enum ('outrigger', 'flat_boat', 'chase_boat', 'speed_boat');
create type public.fuel_type as enum ('gasoline', 'diesel');
create type public.tank_type as enum ('air_12l', 'air_15l', 'nitrox');
create type public.clip_source as enum ('manual', 'returned', 'carryover');
create type public.experience_type as enum ('fun_diving', 'dive_course');
create type public.visit_status as enum ('open', 'closed', 'voided');
create type public.activity_status as enum ('planned', 'scheduled', 'ongoing', 'completed', 'cancelled');
create type public.charge_type as enum ('per_dive', 'per_day');
create type public.payment_method as enum ('cash', 'card', 'online');
create type public.join_ride_direction as enum ('joined_our_boat', 'we_joined_another_boat');
create type public.commission_group as enum ('dive_educator', 'dive_leader');
create type public.commission_status as enum ('unpaid', 'paid');
create type public.rental_gear_status as enum ('to_collect', 'collected', 'to_pay', 'paid');
create type public.expense_category as enum (
  'fuel', 'boat_maintenance', 'equipment_maintenance', 'compressor_fill_station',
  'staff_meals', 'food_expenses', 'office_supplies', 'utilities',
  'licenses_permits', 'marketing', 'repairs', 'other', 'uncategorized'
);

-- =========================================================================
-- 2. Tables
-- =========================================================================

-- ---- Platform layer -----------------------------------------------------

create table public.dive_centers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text,
  phone text,
  address text,
  logo_url text,
  waiver_content text,
  waiver_updated_at timestamptz,
  waiver_content_updated_by uuid, -- FK to public.users added after that table exists
  offers_dive_insurance boolean not null default false,
  insurance_referral_link text,
  pricing_mode public.pricing_mode not null default 'tier',
  subscription_status public.subscription_status not null default 'trial',
  billing_due_date date,
  billing_amount numeric(12,2),
  last_payment_date date,
  billing_unlock_hash text,
  owner_unlock_hash text,
  staff_token text,
  staff_token_date date,
  fuel_current_level numeric(10,2),
  fuel_low_threshold numeric(10,2),
  fuel_gasoline_level numeric(10,2),
  fuel_gasoline_threshold numeric(10,2),
  fuel_gasoline_last_reset_at timestamptz,
  fuel_diesel_level numeric(10,2),
  fuel_diesel_threshold numeric(10,2),
  fuel_diesel_last_reset_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.platform_admins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---- Identity ------------------------------------------------------------

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  full_name text not null,
  email text not null,
  role public.user_role not null default 'secretary',
  can_view_revenue boolean not null default false,
  is_active boolean not null default true,
  password_changed boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.dive_centers
  add constraint dive_centers_waiver_updated_by_fkey
  foreign key (waiver_content_updated_by) references public.users(id);

create table public.staff (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  user_id uuid unique references public.users(id) on delete set null,
  first_name text not null,
  last_name text not null,
  email text,
  phone text,
  whatsapp text,
  position public.staff_position not null default 'crew',
  employment_status public.staff_employment_status,
  date_hired date,
  daily_rate numeric(12,2),
  nitrox_certified boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---- Divers & registration -------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  group_name text not null,
  leader_name text,
  arrival_date date,
  expected_count integer,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.divers (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  age integer,
  birthday date,
  nationality text,
  email text,
  phone text,
  whatsapp text,
  certification_level public.certification_level not null default 'none',
  training_agency public.training_agency,
  logged_dives integer not null default 0,
  nitrox_certified boolean not null default false,
  group_id uuid references public.groups(id) on delete set null,
  needs_equipment boolean not null default false,
  equipment_requested text,
  medical_acknowledged boolean not null default false,
  medical_acknowledged_at timestamptz,
  medical_acknowledged_by uuid references public.users(id),
  cert_card_url text,
  notes text,
  created_at timestamptz not null default now()
);

create index divers_dive_center_email_idx on public.divers (dive_center_id, lower(email));

create table public.diver_registrations (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  group_id uuid references public.groups(id) on delete set null,
  arrival_date date,
  departure_date date,
  accommodation text,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_whatsapp text,
  emergency_contact_email text,
  emergency_contact_relationship text,
  last_dive_date date,
  food_allergies text,
  has_dive_insurance boolean,
  insurance_provider text,
  insurance_policy_number text,
  wants_insurance_referral boolean,
  certification_level public.certification_level,
  equipment_preference text,
  equipment_requested text,
  needs_equipment boolean not null default false,
  medical_answers jsonb,
  medical_answers_snapshot jsonb,
  medical_flag boolean not null default false,
  privacy_consent_at timestamptz,
  privacy_notice_snapshot text,
  waiver_content_snapshot text,
  waiver_date timestamptz,
  waiver_opened boolean not null default false,
  waiver_signature_url text,
  waiver_signed boolean not null default false,
  duplicate_email_flag boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.diver_notes (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  note text not null,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now()
);

create table public.diver_staff_defaults (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  staff_id uuid references public.staff(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (dive_center_id, diver_id)
);

create table public.medical_questions (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  question_text text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true
);

-- Platform-wide singleton, not per-dive-center: the live app confirms this
-- (`.eq('id', true)`, and "[Dive Center Name]" substituted at render time) —
-- one shared privacy notice template across every dive center, maintained by
-- the platform admin, not an individual owner.
create table public.privacy_notice (
  id boolean primary key default true,
  content text not null,
  updated_at timestamptz not null default now(),
  check (id)
);

-- ---- Scheduling & operations ----------------------------------------------

create table public.boats (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  name text not null,
  captain text,
  boat_type public.boat_type,
  fuel_type public.fuel_type,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.dive_sites (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  site_name text not null,
  shark_fee numeric(12,2) not null default 0,
  fuel_estimate numeric(12,2) not null default 0,
  is_active boolean not null default true
);

create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  boat_id uuid references public.boats(id) on delete set null,
  schedule_date date not null,
  departure_time time,
  is_joiner boolean not null default false,
  joiner_boat_name text,
  fuel_consumed_liters numeric(10,2),
  closed boolean not null default false,
  cancelled boolean not null default false,
  notes text,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.schedule_sites (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  schedule_id uuid not null references public.schedules(id) on delete cascade,
  dive_site_id uuid not null references public.dive_sites(id),
  sort_order integer not null default 0,
  unique (schedule_id, dive_site_id)
);

create table public.schedule_divers (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  schedule_id uuid not null references public.schedules(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  staff_id uuid references public.staff(id) on delete set null,
  experience_type public.experience_type,
  is_15l boolean not null default false,
  is_diving_tomorrow boolean not null default false,
  nitrox_requested boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  unique (schedule_id, diver_id)
);

create table public.schedule_day_diver_exclusions (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  schedule_date date not null,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  unique (diver_id, schedule_date)
);

create table public.schedule_team_clips (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  schedule_date date not null,
  staff_id uuid references public.staff(id) on delete set null,
  staff_name text not null default 'Unassigned Staff',
  is_freelancer boolean not null default false,
  source public.clip_source not null default 'manual',
  carry_forward boolean not null default true,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.schedule_team_clip_divers (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  clip_id uuid not null references public.schedule_team_clips(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  excluded_on_date boolean not null default false
);

create table public.manifests (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  schedule_id uuid not null unique references public.schedules(id) on delete cascade,
  district text,
  port text,
  last_edited_at timestamptz not null default now()
);

create table public.fuel_logs (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  boat_id uuid references public.boats(id) on delete set null,
  schedule_id uuid references public.schedules(id) on delete set null,
  fuel_type public.fuel_type,
  liters_consumed numeric(10,2),
  dive_count integer,
  diver_count integer,
  created_at timestamptz not null default now()
);

-- ---- Pricing & rates -------------------------------------------------------

create table public.course_rates (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  course_name text not null,
  rate numeric(12,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.equipment_rental_rates (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  item_name text not null,
  rate numeric(12,2) not null default 0,
  charge_type public.charge_type not null default 'per_day',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.other_charges (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  charge_name text not null,
  amount numeric(12,2) not null default 0,
  charge_type public.charge_type not null,
  sub_type text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.packages (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  package_name text not null,
  dive_site text,
  price numeric(12,2) not null default 0,
  equipment_included boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.rate_tiers (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  tier_name text not null,
  min_dives integer,
  max_dives integer,
  rate numeric(12,2) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.payment_surcharges (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  surcharge_type public.payment_method not null,
  rate numeric(6,4) not null default 0,
  is_active boolean not null default true,
  check (surcharge_type in ('card', 'online'))
);

create table public.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  currency_code text not null,
  rate_to_php numeric(12,6) not null,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique (dive_center_id, currency_code)
);

create table public.govt_fees (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  fee_name text not null,
  amount numeric(12,2) not null default 0,
  is_active boolean not null default true
);

-- ---- Money & transactions ---------------------------------------------------

create table public.visits (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  course_rate_id uuid references public.course_rates(id),
  experience_type public.experience_type not null,
  visit_start date not null default current_date,
  visit_end date,
  visit_status public.visit_status not null default 'open',
  is_active boolean not null default true,
  is_paid boolean not null default false,
  invoice_count integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  visit_id uuid not null references public.visits(id) on delete cascade,
  schedule_id uuid references public.schedules(id) on delete set null,
  date date not null,
  dive_site text,
  staff_name text,
  dive_rate numeric(12,2) not null default 0,
  fuel_surcharge numeric(12,2) not null default 0,
  marine_tax numeric(12,2) not null default 0,
  shark_fee numeric(12,2) not null default 0,
  nitrox_fee numeric(12,2) not null default 0,
  fifteen_l_fee numeric(12,2) not null default 0,
  equipment_rental numeric(12,2) not null default 0,
  equipment_breakdown jsonb,
  addons numeric(12,2) not null default 0,
  addon_breakdown jsonb,
  discount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0, -- server-computed, see compute_activity_total trigger below
  status public.activity_status not null default 'planned',
  flags jsonb, -- structured replacement for the old JSON-encoded `notes` text blob
  notes text,
  created_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  visit_id uuid not null unique references public.visits(id) on delete cascade,
  cash_amount numeric(12,2) not null default 0,
  cash_amount_foreign numeric(12,2),
  cash_currency_code text,
  cash_exchange_rate numeric(12,6),
  card_amount numeric(12,2) not null default 0,
  online_amount numeric(12,2) not null default 0,
  total_paid numeric(12,2) not null default 0,
  balance numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0,
  grand_total_php numeric(12,2) not null default 0,
  card_surcharge_rate numeric(6,4) not null default 0,
  online_surcharge_rate numeric(6,4) not null default 0,
  card_surcharge_amount numeric(12,2) not null default 0,
  online_surcharge_amount numeric(12,2) not null default 0,
  total_surcharge numeric(12,2) not null default 0,
  total_collected numeric(12,2) not null default 0,
  is_paid boolean not null default false,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.deposits (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  visit_id uuid references public.visits(id) on delete cascade,
  amount numeric(12,2) not null,
  method public.payment_method not null,
  deposit_date date not null default current_date,
  received_by text,
  recorded_by_user_id uuid references public.users(id),
  created_at timestamptz not null default now()
);

create table public.visit_rate_selections (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  visit_id uuid not null references public.visits(id) on delete cascade,
  site_key text not null,
  package_id uuid references public.packages(id),
  custom_price numeric(12,2),
  unique (visit_id, site_key)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  date date not null,
  category public.expense_category not null,
  custom_category text,
  amount numeric(12,2) not null check (amount > 0),
  paid_by text,
  notes text,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now()
);

create table public.invoice_emails (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  diver_id uuid not null references public.divers(id) on delete cascade,
  visit_id uuid not null references public.visits(id) on delete cascade,
  invoice_snapshot jsonb,
  sent_at timestamptz not null default now(),
  sent_by uuid references public.users(id)
);

create table public.join_ride_statements (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  company text not null,
  date_from date,
  date_to date,
  total_amount numeric(12,2) not null default 0,
  status text not null default 'statement_printed',
  prepared_by text,
  printed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.join_ride_records (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  direction public.join_ride_direction not null,
  date date not null,
  company text not null,
  number_of_divers integer,
  number_of_dives integer,
  dive_sites text,
  total_amount numeric(12,2) not null default 0,
  status text not null,
  balance numeric(12,2) not null default 0,
  remarks text,
  statement_id uuid references public.join_ride_statements(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (direction = 'joined_our_boat' and status in ('to_collect', 'statement_printed', 'collected'))
    or
    (direction = 'we_joined_another_boat' and status in ('expected_to_pay', 'statement_received', 'paid'))
  )
);

create table public.staff_commission_records (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  period_month text not null check (period_month ~ '^\d{4}-\d{2}$'),
  staff_name text not null,
  commission_group public.commission_group not null,
  title text,
  quantity integer not null default 0,
  rate numeric(12,2) not null default 0,
  commission_amount numeric(12,2) not null default 0,
  status public.commission_status not null default 'unpaid',
  paid_at timestamptz,
  remarks text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.rental_gear_records (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  date date not null,
  equipment text not null,
  company text,
  quantity integer not null default 0,
  rate numeric(12,2) not null default 0,
  total_amount numeric(12,2) not null default 0,
  status public.rental_gear_status not null default 'to_collect',
  balance numeric(12,2) not null default 0,
  remarks text,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ---- Inventory --------------------------------------------------------------

create table public.equipment (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  name text not null,
  type text,
  total_count integer not null default 0,
  low_alert_threshold integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.tanks (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid not null references public.dive_centers(id) on delete cascade,
  type public.tank_type not null,
  total_count integer not null default 0,
  available_count integer not null default 0,
  in_use_count integer not null default 0,
  low_alert_threshold integer not null default 0,
  unique (dive_center_id, type)
);

-- ---- System -------------------------------------------------------------------

-- No FK on dive_center_id/performed_by: an audit trail must survive deletion
-- of the tenant or user it's recording, so it deliberately does not hard-depend
-- on either row still existing (same reasoning as target_id being polymorphic).
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  dive_center_id uuid,
  action text not null,
  target_type text not null,
  target_id uuid,
  performed_by uuid,
  notes text,
  created_at timestamptz not null default now()
);

-- =========================================================================
-- 3. Helper functions (used throughout RLS policies)
-- =========================================================================

create or replace function public.current_dive_center_id()
returns uuid
language sql stable security definer set search_path = public as $$
  select dive_center_id from public.users where id = auth.uid();
$$;

create or replace function public.is_owner()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'owner' from public.users where id = auth.uid()), false);
$$;

create or replace function public.current_can_view_revenue()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role = 'owner' or can_view_revenue = true from public.users where id = auth.uid()),
    false
  );
$$;

create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.platform_admins where user_id = auth.uid() and is_active = true
  );
$$;

-- =========================================================================
-- 4. Trigger functions
-- =========================================================================

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  NEW.updated_at = now();
  return NEW;
end;
$$;

create or replace function public.compute_activity_total()
returns trigger language plpgsql as $$
begin
  NEW.total := coalesce(NEW.dive_rate,0) + coalesce(NEW.fuel_surcharge,0) + coalesce(NEW.marine_tax,0)
    + coalesce(NEW.shark_fee,0) + coalesce(NEW.nitrox_fee,0) + coalesce(NEW.fifteen_l_fee,0)
    + coalesce(NEW.equipment_rental,0) + coalesce(NEW.addons,0) - coalesce(NEW.discount,0);
  return NEW;
end;
$$;

create or replace function public.enforce_registration_immutability()
returns trigger language plpgsql as $$
begin
  if OLD.waiver_signed = true then
    raise exception 'diver_registrations row % is immutable once waiver_signed is true', OLD.id;
  end if;
  return NEW;
end;
$$;

-- Restrict a platform admin's UPDATE on dive_centers to billing/status fields only.
create or replace function public.enforce_dive_center_update_scope()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_platform_admin() and not public.is_owner() then
    if (to_jsonb(NEW) - array['subscription_status','billing_due_date','billing_amount','last_payment_date'])
       is distinct from
       (to_jsonb(OLD) - array['subscription_status','billing_due_date','billing_amount','last_payment_date'])
    then
      raise exception 'platform admin may only modify subscription/billing fields on dive_centers';
    end if;
  end if;
  return NEW;
end;
$$;

-- Restrict a non-owner user updating their own row to a small self-service field set.
create or replace function public.enforce_users_self_update_scope()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() = OLD.id and not public.is_owner() then
    if (to_jsonb(NEW) - array['full_name','password_changed'])
       is distinct from
       (to_jsonb(OLD) - array['full_name','password_changed'])
    then
      raise exception 'cannot modify restricted fields on your own user record';
    end if;
  end if;
  return NEW;
end;
$$;

create or replace function public.log_audit_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_dive_center_id uuid;
  v_row jsonb;
begin
  v_row := to_jsonb(coalesce(NEW, OLD));
  if TG_TABLE_NAME = 'dive_centers' then
    v_dive_center_id := (v_row->>'id')::uuid;
  else
    v_dive_center_id := (v_row->>'dive_center_id')::uuid;
  end if;
  insert into public.audit_logs (dive_center_id, action, target_type, target_id, performed_by)
  values (v_dive_center_id, lower(TG_OP), TG_TABLE_NAME, coalesce(NEW.id, OLD.id), auth.uid());
  return coalesce(NEW, OLD);
end;
$$;

-- =========================================================================
-- 5. Attach triggers
-- =========================================================================

create trigger schedules_set_updated_at before update on public.schedules
  for each row execute function public.set_updated_at();
create trigger schedule_team_clips_set_updated_at before update on public.schedule_team_clips
  for each row execute function public.set_updated_at();
create trigger exchange_rates_set_updated_at before update on public.exchange_rates
  for each row execute function public.set_updated_at();
create trigger join_ride_statements_set_updated_at before update on public.join_ride_statements
  for each row execute function public.set_updated_at();
create trigger join_ride_records_set_updated_at before update on public.join_ride_records
  for each row execute function public.set_updated_at();
create trigger staff_commission_records_set_updated_at before update on public.staff_commission_records
  for each row execute function public.set_updated_at();
create trigger rental_gear_records_set_updated_at before update on public.rental_gear_records
  for each row execute function public.set_updated_at();

create trigger activities_compute_total before insert or update on public.activities
  for each row execute function public.compute_activity_total();

create trigger diver_registrations_immutable before update on public.diver_registrations
  for each row execute function public.enforce_registration_immutability();

create trigger dive_centers_update_scope before update on public.dive_centers
  for each row execute function public.enforce_dive_center_update_scope();

create trigger users_self_update_scope before update on public.users
  for each row execute function public.enforce_users_self_update_scope();

create trigger audit_payments after insert or update or delete on public.payments
  for each row execute function public.log_audit_event();
create trigger audit_diver_registrations after insert or update or delete on public.diver_registrations
  for each row execute function public.log_audit_event();
create trigger audit_visits after insert or update or delete on public.visits
  for each row execute function public.log_audit_event();
create trigger audit_dive_centers after insert or update or delete on public.dive_centers
  for each row execute function public.log_audit_event();
create trigger audit_users after insert or update or delete on public.users
  for each row execute function public.log_audit_event();
create trigger audit_staff after insert or update or delete on public.staff
  for each row execute function public.log_audit_event();

-- Auto-create the manifest row for every new schedule (the live app has no
-- client-side insert path for `manifests` at all — this replaces whatever
-- server-side mechanism must have been doing it there).
create or replace function public.create_manifest_for_schedule()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.manifests (dive_center_id, schedule_id)
  values (NEW.dive_center_id, NEW.id);
  return NEW;
end;
$$;

create trigger schedules_create_manifest after insert on public.schedules
  for each row execute function public.create_manifest_for_schedule();

-- =========================================================================
-- 6. Server-side functions (Stage 1a additions beyond the legacy 4 RPCs)
-- =========================================================================

create or replace function public.calculate_visit_total(p_visit_id uuid)
returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(a.total), 0)
  from public.activities a
  where a.visit_id = p_visit_id
    and a.status <> 'cancelled';
$$;

create or replace function public.set_billing_unlock(p_dive_center_id uuid, p_secret text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not (public.is_owner() and public.current_dive_center_id() = p_dive_center_id) then
    raise exception 'only the owner of this dive center may set the billing unlock secret';
  end if;
  update public.dive_centers
    set billing_unlock_hash = crypt(p_secret, gen_salt('bf'))
    where id = p_dive_center_id;
end;
$$;

create or replace function public.set_owner_unlock(p_dive_center_id uuid, p_secret text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not (public.is_owner() and public.current_dive_center_id() = p_dive_center_id) then
    raise exception 'only the owner of this dive center may set the owner unlock secret';
  end if;
  update public.dive_centers
    set owner_unlock_hash = crypt(p_secret, gen_salt('bf'))
    where id = p_dive_center_id;
end;
$$;

create or replace function public.verify_billing_unlock(p_dive_center_id uuid, p_attempt text)
returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select billing_unlock_hash is not null
    and billing_unlock_hash = crypt(p_attempt, billing_unlock_hash)
  from public.dive_centers
  where id = p_dive_center_id;
$$;

create or replace function public.verify_owner_unlock(p_dive_center_id uuid, p_attempt text)
returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select owner_unlock_hash is not null
    and owner_unlock_hash = crypt(p_attempt, owner_unlock_hash)
  from public.dive_centers
  where id = p_dive_center_id;
$$;

-- NOTE: the legacy RPCs check_returning_diver, get_diver_prefill,
-- update_returning_diver_registration, and set_diver_cert_card_url are
-- intentionally NOT reimplemented here. Their real logic lives only in the
-- live production database, which this build never connects to, and their
-- calling code in register.html/diver-form.html doesn't fully specify their
-- internal behavior. These get built for real in Stage 3 when the
-- registration flow is rebuilt, using this schema as the target.

-- =========================================================================
-- 7. Row Level Security
-- =========================================================================

-- ---- Platform layer ----

alter table public.platform_admins enable row level security;
create policy platform_admins_self_select on public.platform_admins for select
  using (user_id = auth.uid());

alter table public.dive_centers enable row level security;
create policy dive_centers_select on public.dive_centers for select
  using (id = public.current_dive_center_id() or public.is_platform_admin());
create policy dive_centers_update_owner on public.dive_centers for update
  using (id = public.current_dive_center_id() and public.is_owner())
  with check (id = public.current_dive_center_id() and public.is_owner());
create policy dive_centers_update_platform_admin on public.dive_centers for update
  using (public.is_platform_admin())
  with check (public.is_platform_admin());
-- No client-side INSERT/DELETE policy: dive center creation/removal happens
-- only via a service-role Edge Function (platform admin console backend).

-- ---- Identity ----

alter table public.users enable row level security;
create policy users_select on public.users for select
  using (dive_center_id = public.current_dive_center_id());
create policy users_owner_write on public.users for all
  using (dive_center_id = public.current_dive_center_id() and public.is_owner())
  with check (dive_center_id = public.current_dive_center_id() and public.is_owner());
create policy users_self_update on public.users for update
  using (id = auth.uid())
  with check (id = auth.uid());

alter table public.staff enable row level security;
create policy staff_select on public.staff for select
  using (dive_center_id = public.current_dive_center_id());
create policy staff_owner_write on public.staff for all
  using (dive_center_id = public.current_dive_center_id() and public.is_owner())
  with check (dive_center_id = public.current_dive_center_id() and public.is_owner());

-- ---- Generic "operational" tables: both tiers read + write within their tenant ----
-- (divers, registration, scheduling, manifests, day-to-day money entry)

do $$
declare
  t text;
  operational_tables text[] := array[
    'groups', 'divers', 'diver_staff_defaults',
    'schedules', 'schedule_sites', 'schedule_divers', 'schedule_day_diver_exclusions',
    'schedule_team_clips', 'schedule_team_clip_divers', 'manifests', 'fuel_logs',
    'visits', 'activities', 'payments', 'deposits', 'visit_rate_selections', 'invoice_emails'
  ];
begin
  foreach t in array operational_tables loop
    execute format('alter table public.%I enable row level security;', t);
    execute format(
      'create policy %I_select on public.%I for select using (dive_center_id = public.current_dive_center_id());',
      t, t
    );
    execute format(
      'create policy %I_insert on public.%I for insert with check (dive_center_id = public.current_dive_center_id());',
      t, t
    );
    execute format(
      'create policy %I_update on public.%I for update using (dive_center_id = public.current_dive_center_id()) with check (dive_center_id = public.current_dive_center_id());',
      t, t
    );
    execute format(
      'create policy %I_delete on public.%I for delete using (dive_center_id = public.current_dive_center_id());',
      t, t
    );
  end loop;
end $$;

-- diver_notes: insert-only pattern (matches how the live app behaves) — owner may delete for corrections, nobody may update.
alter table public.diver_notes enable row level security;
create policy diver_notes_select on public.diver_notes for select
  using (dive_center_id = public.current_dive_center_id());
create policy diver_notes_insert on public.diver_notes for insert
  with check (dive_center_id = public.current_dive_center_id());
create policy diver_notes_delete_owner on public.diver_notes for delete
  using (dive_center_id = public.current_dive_center_id() and public.is_owner());

-- diver_registrations: both tiers read/write, but the immutability trigger above
-- blocks any update once waiver_signed = true, regardless of role.
alter table public.diver_registrations enable row level security;
create policy diver_registrations_select on public.diver_registrations for select
  using (dive_center_id = public.current_dive_center_id());
create policy diver_registrations_insert on public.diver_registrations for insert
  with check (dive_center_id = public.current_dive_center_id());
create policy diver_registrations_update on public.diver_registrations for update
  using (dive_center_id = public.current_dive_center_id())
  with check (dive_center_id = public.current_dive_center_id());
create policy diver_registrations_delete_owner on public.diver_registrations for delete
  using (dive_center_id = public.current_dive_center_id() and public.is_owner());

-- ---- "Settings tier" tables: owner-writable, secretary-readable ----

do $$
declare
  t text;
  settings_tables text[] := array[
    'boats', 'dive_sites', 'medical_questions',
    'course_rates', 'equipment_rental_rates', 'other_charges', 'packages', 'rate_tiers',
    'payment_surcharges', 'exchange_rates', 'govt_fees',
    'equipment', 'tanks'
  ];
begin
  foreach t in array settings_tables loop
    execute format('alter table public.%I enable row level security;', t);
    execute format(
      'create policy %I_select on public.%I for select using (dive_center_id = public.current_dive_center_id());',
      t, t
    );
    execute format(
      'create policy %I_owner_write on public.%I for all using (dive_center_id = public.current_dive_center_id() and public.is_owner()) with check (dive_center_id = public.current_dive_center_id() and public.is_owner());',
      t, t
    );
  end loop;
end $$;

-- privacy_notice: platform-wide singleton, readable by anyone (including the
-- anonymous public registration page), writable only by the platform admin.
alter table public.privacy_notice enable row level security;
create policy privacy_notice_select_all on public.privacy_notice for select
  using (true);
create policy privacy_notice_write_platform_admin on public.privacy_notice for all
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

-- ---- Revenue-gated "reports" tables: owner always, secretary only with can_view_revenue ----

do $$
declare
  t text;
  revenue_tables text[] := array[
    'expenses', 'staff_commission_records', 'rental_gear_records',
    'join_ride_records', 'join_ride_statements'
  ];
begin
  foreach t in array revenue_tables loop
    execute format('alter table public.%I enable row level security;', t);
    execute format(
      'create policy %I_select on public.%I for select using (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue());',
      t, t
    );
    execute format(
      'create policy %I_write on public.%I for all using (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue()) with check (dive_center_id = public.current_dive_center_id() and public.current_can_view_revenue());',
      t, t
    );
  end loop;
end $$;

-- ---- System ----

alter table public.audit_logs enable row level security;
create policy audit_logs_select_owner on public.audit_logs for select
  using (dive_center_id = public.current_dive_center_id() and public.is_owner());
-- No client insert/update/delete policy: rows are written only by the
-- SECURITY DEFINER log_audit_event() trigger function, which bypasses RLS.
