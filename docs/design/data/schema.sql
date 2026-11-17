-- =============================================================================
-- HomeMate AI — PA3 Data Design (SCRUM-27 / SCRUM-28)
-- Target: Supabase PostgreSQL 15+ (tested on PostgreSQL 16)
-- Owner: Tran Gia Huy (Developer)
--
-- Scope: Must-have features F01–F04 + account/project access (PA2 FR-01..FR-23).
-- Optional F05–F07 (checklists, evidence, alerts) are NOT part of this baseline;
-- they will be added by a separate migration only if implemented.
--
-- Conventions
--   * snake_case, plural table names, UUID primary keys (gen_random_uuid()).
--   * Money is stored in whole VND as BIGINT (BR-04, NFR-06): no floating point.
--   * Values that can be derived (spent, remaining, wage totals, threshold state)
--     are NOT stored; they are computed by the views at the end of this file.
--   * Authorization (RLS, RPC functions) lives in rls-policies.sql.
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- 1. Enumerated types
-- -----------------------------------------------------------------------------
create type public.construction_type as enum ('new_build', 'renovation');
create type public.project_status    as enum ('active', 'completed', 'archived');
create type public.member_status     as enum ('invited', 'active', 'revoked');
create type public.stage_status      as enum ('not_started', 'in_progress', 'completed');
create type public.rate_type         as enum ('daily', 'hourly');
create type public.attendance_status as enum ('absent', 'half_day', 'full_day', 'hourly');
create type public.chat_role         as enum ('user', 'assistant');

-- -----------------------------------------------------------------------------
-- 2. Shared trigger: keep updated_at current
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Tables
-- -----------------------------------------------------------------------------

-- 3.1 profiles: application data for a Supabase Auth user (1:1 with auth.users).
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null check (char_length(full_name) between 1 and 100),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 3.2 projects: one construction / renovation project owned by one homeowner.
create table public.projects (
  id                 uuid primary key default gen_random_uuid(),
  owner_id           uuid not null references public.profiles (id) on delete cascade,
  name               text not null check (char_length(name) between 1 and 120),
  construction_type  public.construction_type not null,
  floor_count        smallint check (floor_count between 1 and 20),
  floor_area_m2      numeric(8,2) check (floor_area_m2 > 0),
  target_start_date  date,
  target_end_date    date,
  status             public.project_status not null default 'active',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint projects_target_dates_chk                       -- BR-07 (applied to project dates)
    check (target_end_date is null or target_start_date is null
           or target_end_date >= target_start_date)
);

-- 3.3 project_budgets: total planned budget, kept apart from projects so that
--     crew leaders (who may read projects) never see financial data (BR-02/03).
create table public.project_budgets (
  project_id            uuid primary key references public.projects (id) on delete cascade,
  total_planned_amount  bigint not null check (total_planned_amount > 0),  -- UC-03 E1
  updated_at            timestamptz not null default now()
);

-- 3.4 project_members: crew leaders invited to a project and their two scoped
--     permissions (FR-04). The owner is NOT a member row; ownership = projects.owner_id.
create table public.project_members (
  id                          uuid primary key default gen_random_uuid(),
  project_id                  uuid not null references public.projects (id) on delete cascade,
  user_id                     uuid not null references public.profiles (id) on delete cascade,
  status                      public.member_status not null default 'invited',
  can_record_attendance       boolean not null default false,
  can_update_assigned_stages  boolean not null default false,
  invited_at                  timestamptz not null default now(),
  accepted_at                 timestamptz,
  updated_at                  timestamptz not null default now(),
  constraint project_members_uq unique (project_id, user_id),
  constraint project_members_id_project_uq unique (id, project_id)   -- target of composite FK
);

-- 3.5 budget_categories: planned allocation per expense category (FR-05, FR-06).
--     Default set: Rough Construction, Finishing, Labour, Contingency (UC-03).
create table public.budget_categories (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects (id) on delete cascade,
  name            text not null check (char_length(name) between 1 and 60),
  planned_amount  bigint not null default 0 check (planned_amount >= 0),
  sort_order      smallint not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint budget_categories_name_uq unique (project_id, name),
  constraint budget_categories_id_project_uq unique (id, project_id)
);

-- 3.6 stages: confirmed construction stages only. AI drafts are never stored
--     here until the owner confirms them (BR-08, NFR-08, AD-03).
create table public.stages (
  id                  uuid primary key default gen_random_uuid(),
  project_id          uuid not null references public.projects (id) on delete cascade,
  name                text not null check (char_length(name) between 1 and 120),
  sequence_order      integer not null check (sequence_order > 0),
  planned_start_date  date,
  planned_end_date    date,
  actual_start_date   date,
  actual_end_date     date,
  status              public.stage_status not null default 'not_started',
  progress_note       text check (char_length(progress_note) <= 2000),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint stages_planned_dates_chk                        -- BR-07
    check (planned_end_date is null or planned_start_date is null
           or planned_end_date >= planned_start_date),
  constraint stages_actual_dates_chk                         -- BR-07 / UC-07 E1
    check (actual_end_date is null or actual_start_date is null
           or actual_end_date >= actual_start_date),
  constraint stages_order_uq unique (project_id, sequence_order)
    deferrable initially deferred,                           -- allows reordering in one transaction
  constraint stages_id_project_uq unique (id, project_id)
);

-- 3.7 stage_assignments: which crew leader may update which stage (FR-16, BR-03).
--     Composite FKs guarantee the stage and the member belong to the same project.
create table public.stage_assignments (
  project_id   uuid not null,
  stage_id     uuid not null,
  member_id    uuid not null,
  assigned_at  timestamptz not null default now(),
  primary key (stage_id, member_id),
  foreign key (stage_id, project_id)
    references public.stages (id, project_id) on delete cascade,
  foreign key (member_id, project_id)
    references public.project_members (id, project_id) on delete cascade
);

-- 3.8 expenses: material and labour expense records (FR-07..FR-09).
create table public.expenses (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid not null references public.projects (id) on delete cascade,
  category_id       uuid not null,
  stage_id          uuid,
  item_name         text not null check (char_length(item_name) between 1 and 200),
  quantity          numeric(12,3) not null check (quantity > 0),          -- BR-05
  unit              text not null check (char_length(unit) between 1 and 30),
  unit_price        bigint not null check (unit_price > 0),              -- BR-05, VND
  line_total        bigint generated always as
                      ((round(quantity * unit_price))::bigint) stored,   -- FR-09, rounded to 1 VND
  transaction_date  date not null,
  note              text check (char_length(note) <= 1000),
  created_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  foreign key (category_id, project_id)
    references public.budget_categories (id, project_id) on delete restrict,
  foreign key (stage_id, project_id)
    references public.stages (id, project_id) on delete set null (stage_id)
);

-- 3.9 workers: worker / crew profiles with agreed rates (FR-17, FR-18).
create table public.workers (
  id           uuid primary key default gen_random_uuid(),
  project_id   uuid not null references public.projects (id) on delete cascade,
  full_name    text not null check (char_length(full_name) between 1 and 100),
  phone        text check (phone ~ '^0[0-9]{9}$'),                       -- VN mobile format
  trade        text not null check (char_length(trade) between 1 and 50), -- Mason, Electrician...
  rate_type    public.rate_type not null,
  agreed_rate  bigint not null check (agreed_rate > 0),                 -- BR-05, VND per day/hour
  is_active    boolean not null default true,                           -- soft deactivation (FR-18)
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint workers_id_project_uq unique (id, project_id)
);

-- 3.10 attendance_records: one row per worker per date (FR-19, BR-09, BR-10).
--      rate_type_snapshot and captured_rate copy the worker's rate at creation
--      time so later rate changes do not alter past estimates (BR-11).
create table public.attendance_records (
  id                  uuid primary key default gen_random_uuid(),
  project_id          uuid not null,
  worker_id           uuid not null,
  work_date           date not null,                     -- calendar date in Asia/Ho_Chi_Minh
  status              public.attendance_status not null,
  units               numeric(4,2) not null,             -- days (0/0.5/1) or hours (0..24)
  rate_type_snapshot  public.rate_type not null,
  captured_rate       bigint not null check (captured_rate > 0),
  note                text check (char_length(note) <= 500),
  recorded_by         uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  foreign key (worker_id, project_id)
    references public.workers (id, project_id) on delete restrict,     -- UC-08 E2: no hard delete
  constraint attendance_one_per_day_uq unique (worker_id, work_date),  -- BR-10
  constraint attendance_units_chk check (                              -- BR-09
       (status = 'absent'   and units = 0)
    or (status = 'half_day' and units = 0.5)
    or (status = 'full_day' and units = 1)
    or (status = 'hourly'   and units > 0 and units <= 24)),
  constraint attendance_status_matches_rate_chk check (
       (rate_type_snapshot = 'daily'  and status in ('absent', 'half_day', 'full_day'))
    or (rate_type_snapshot = 'hourly' and status in ('absent', 'hourly')))
);

-- 3.11 ai_chat_messages: AI Q&A history; the last few turns are included in the
--      bounded context (FR-21). Owner-only.
create table public.ai_chat_messages (
  id          uuid primary key default gen_random_uuid(),
  project_id  uuid not null references public.projects (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        public.chat_role not null,
  content     text not null check (char_length(content) between 1 and 8000),
  created_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 4. Business-rule triggers
-- -----------------------------------------------------------------------------

-- 4.1 BR-01: at most two active projects per owner. The owner's profile row is
--     locked first so two concurrent inserts cannot both pass the check.
create or replace function public.enforce_active_project_limit()
returns trigger language plpgsql as $$
declare
  active_count integer;
begin
  if new.status <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'active' and old.owner_id = new.owner_id then
    return new;                                   -- no change to the active count
  end if;

  perform 1 from public.profiles where id = new.owner_id for update;

  select count(*) into active_count
  from public.projects
  where owner_id = new.owner_id and status = 'active' and id <> new.id;

  if active_count >= 2 then
    raise exception 'ACTIVE_PROJECT_LIMIT: an owner may have at most 2 active projects'
      using errcode = 'P0001', hint = 'BR-01';
  end if;
  return new;
end $$;

create trigger projects_active_limit
  before insert or update of status, owner_id on public.projects
  for each row execute function public.enforce_active_project_limit();

-- 4.2 BR-11: snapshot the worker's rate onto each attendance record. On insert
--     the values always come from workers (client input is ignored); on update
--     they are frozen. Inactive workers cannot receive new attendance.
--     SECURITY DEFINER because crew leaders cannot read workers.agreed_rate.
create or replace function public.snapshot_attendance_rate()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  w record;
begin
  if tg_op = 'INSERT' then
    select rate_type, agreed_rate, is_active into w
    from public.workers
    where id = new.worker_id and project_id = new.project_id;

    if not found then
      raise exception 'WORKER_NOT_IN_PROJECT' using errcode = 'P0001';
    end if;
    if not w.is_active then
      raise exception 'WORKER_INACTIVE: cannot record attendance for a deactivated worker'
        using errcode = 'P0001', hint = 'FR-18';
    end if;
    new.rate_type_snapshot := w.rate_type;
    new.captured_rate      := w.agreed_rate;
  else
    new.rate_type_snapshot := old.rate_type_snapshot;
    new.captured_rate      := old.captured_rate;
    new.worker_id          := old.worker_id;
    new.project_id         := old.project_id;
  end if;
  return new;
end $$;

create trigger attendance_snapshot_rate
  before insert or update on public.attendance_records
  for each row execute function public.snapshot_attendance_rate();

-- 4.3 updated_at maintenance
create trigger profiles_updated_at          before update on public.profiles          for each row execute function public.set_updated_at();
create trigger projects_updated_at          before update on public.projects          for each row execute function public.set_updated_at();
create trigger project_budgets_updated_at   before update on public.project_budgets   for each row execute function public.set_updated_at();
create trigger project_members_updated_at   before update on public.project_members   for each row execute function public.set_updated_at();
create trigger budget_categories_updated_at before update on public.budget_categories for each row execute function public.set_updated_at();
create trigger stages_updated_at            before update on public.stages            for each row execute function public.set_updated_at();
create trigger expenses_updated_at          before update on public.expenses          for each row execute function public.set_updated_at();
create trigger workers_updated_at           before update on public.workers           for each row execute function public.set_updated_at();
create trigger attendance_updated_at        before update on public.attendance_records for each row execute function public.set_updated_at();

-- 4.4 Create a profile automatically when a user signs up (Supabase Auth).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'full_name', ''),
                           split_part(new.email, '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- 5. Indexes for frequent queries (foreign keys are not indexed automatically)
-- -----------------------------------------------------------------------------
create index projects_owner_active_idx    on public.projects (owner_id) where status = 'active';
create index project_members_user_idx     on public.project_members (user_id) where status = 'active';
create index stage_assignments_member_idx on public.stage_assignments (member_id);
create index stage_assignments_proj_idx   on public.stage_assignments (project_id);
create index expenses_project_date_idx    on public.expenses (project_id, transaction_date desc);
create index expenses_category_idx        on public.expenses (category_id);
create index expenses_stage_idx           on public.expenses (stage_id) where stage_id is not null;
create index workers_project_active_idx   on public.workers (project_id) where is_active;
create index attendance_project_date_idx  on public.attendance_records (project_id, work_date);
create index ai_chat_project_time_idx     on public.ai_chat_messages (project_id, created_at desc);
-- Already covered by UNIQUE constraints: budget_categories(project_id, name),
-- stages(project_id, sequence_order), attendance_records(worker_id, work_date),
-- project_members(project_id, user_id).

-- -----------------------------------------------------------------------------
-- 6. Derived-data views (security_invoker: the caller's RLS applies)
-- -----------------------------------------------------------------------------

-- 6.1 Category spending and threshold indicator (FR-10, FR-11, BR-06).
create view public.v_category_spending with (security_invoker = true) as
select c.project_id,
       c.id                                   as category_id,
       c.name,
       c.sort_order,
       c.planned_amount,
       coalesce(sum(e.line_total), 0)::bigint as actual_spent,
       (c.planned_amount - coalesce(sum(e.line_total), 0))::bigint as remaining,
       case when c.planned_amount = 0 then null
            else round(coalesce(sum(e.line_total), 0)::numeric / c.planned_amount, 4)
       end                                    as spending_ratio,
       case
         when c.planned_amount = 0 and coalesce(sum(e.line_total), 0) = 0 then 'normal'
         when c.planned_amount = 0 then 'reached'
         when coalesce(sum(e.line_total), 0) >= c.planned_amount        then 'reached'
         when coalesce(sum(e.line_total), 0) * 100 >= c.planned_amount * 85 then 'warning'
         else 'normal'
       end                                    as threshold_state
from public.budget_categories c
left join public.expenses e on e.category_id = c.id
group by c.id;

-- 6.2 Project financial summary for the dashboard (FR-10; zero-expense safe, UC-05 E1).
create view public.v_project_financial_summary with (security_invoker = true) as
select p.id                                           as project_id,
       b.total_planned_amount,
       coalesce(sum(e.line_total), 0)::bigint         as total_actual_spent,
       (b.total_planned_amount - coalesce(sum(e.line_total), 0))::bigint as remaining_balance,
       (select coalesce(sum(planned_amount), 0) from public.budget_categories c
         where c.project_id = p.id)::bigint           as total_allocated   -- UC-03 E2 check
from public.projects p
join public.project_budgets b on b.project_id = p.id
left join public.expenses e   on e.project_id = p.id
group by p.id, b.total_planned_amount;

-- 6.3 Per-record wage estimate (FR-20). Period totals: filter work_date and SUM.
create view public.v_attendance_wages with (security_invoker = true) as
select a.project_id,
       a.worker_id,
       a.work_date,
       a.status,
       a.units,
       a.captured_rate,
       (round(a.units * a.captured_rate))::bigint as estimated_wage
from public.attendance_records a;

-- -----------------------------------------------------------------------------
-- 7. Default expense categories for a new project (UC-03 main flow, step 3)
-- -----------------------------------------------------------------------------
create or replace function public.seed_default_categories()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.budget_categories (project_id, name, sort_order)
  values (new.id, 'Rough Construction', 1),
         (new.id, 'Finishing',          2),
         (new.id, 'Labour',             3),
         (new.id, 'Contingency',        4);
  return new;
end $$;

create trigger projects_seed_categories
  after insert on public.projects
  for each row execute function public.seed_default_categories();
