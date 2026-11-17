-- =============================================================================
-- HomeMate AI — PA3 Authentication, Authorization & RLS Design (SCRUM-29)
-- Run after schema.sql. Target: Supabase PostgreSQL 15+.
--
-- Principles
--   1. Deny by default: RLS is enabled on every table; no policy = no access.
--   2. The owner of a project (projects.owner_id) has full access to it.
--   3. A crew leader is an ACTIVE row in project_members with two flags:
--        can_record_attendance       -> attendance through upsert_attendance() only
--        can_update_assigned_stages  -> progress of ASSIGNED stages through
--                                       update_stage_progress() only
--      Crew leaders never read budgets, expenses, wage rates, phone numbers or
--      AI chats (BR-02, BR-03, NFR-03).
--   4. Column-restricted operations go through SECURITY DEFINER functions that
--      check permissions themselves, because RLS works on rows, not columns.
--   5. Security definer helpers live in schema "private", which is not exposed
--      by the Supabase Data API, and pin search_path to ''.
--   6. auth.uid() is wrapped as (select auth.uid()) so it is evaluated once
--      per statement (Supabase performance guidance).
-- =============================================================================

create schema if not exists private;
grant usage on schema private to authenticated;

-- -----------------------------------------------------------------------------
-- 1. Helper functions
-- -----------------------------------------------------------------------------
create or replace function private.is_project_owner(p_project_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.projects
    where id = p_project_id and owner_id = (select auth.uid()));
$$;

create or replace function private.is_active_member(p_project_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.project_members
    where project_id = p_project_id and user_id = (select auth.uid())
      and status = 'active');
$$;

-- p_permission: 'attendance' | 'stages'. The owner implicitly has both.
create or replace function private.has_permission(p_project_id uuid, p_permission text)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_project_owner(p_project_id)
      or exists (
        select 1 from public.project_members m
        where m.project_id = p_project_id
          and m.user_id = (select auth.uid())
          and m.status = 'active'
          and case p_permission
                when 'attendance' then m.can_record_attendance
                when 'stages'     then m.can_update_assigned_stages
                else false
              end);
$$;

create or replace function private.is_assigned_stage(p_stage_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.stage_assignments sa
    join public.project_members m on m.id = sa.member_id
    where sa.stage_id = p_stage_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.can_update_assigned_stages);
$$;

grant execute on all functions in schema private to authenticated;

-- -----------------------------------------------------------------------------
-- 2. Enable RLS on every table
-- -----------------------------------------------------------------------------
alter table public.profiles           enable row level security;
alter table public.projects           enable row level security;
alter table public.project_budgets    enable row level security;
alter table public.project_members    enable row level security;
alter table public.budget_categories  enable row level security;
alter table public.stages             enable row level security;
alter table public.stage_assignments  enable row level security;
alter table public.expenses           enable row level security;
alter table public.workers            enable row level security;
alter table public.attendance_records enable row level security;
alter table public.ai_chat_messages   enable row level security;

-- -----------------------------------------------------------------------------
-- 3. Policies
-- -----------------------------------------------------------------------------

-- profiles: a user sees their own profile and the profiles of people they share
-- a project with (owner <-> crew leader), e.g. on the Project Access screen.
create policy profiles_select on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or exists (select 1 from public.project_members m
               where m.user_id = profiles.id and private.is_project_owner(m.project_id))
    or exists (select 1 from public.projects p
               where p.owner_id = profiles.id and private.is_active_member(p.id)));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- projects: owner full access; active crew leaders may read the project header.
create policy projects_select on public.projects for select to authenticated
  using (owner_id = (select auth.uid()) or private.is_active_member(id));
create policy projects_insert on public.projects for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy projects_update on public.projects for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy projects_delete on public.projects for delete to authenticated
  using (owner_id = (select auth.uid()));

-- Owner-only tables: budgets, categories, expenses, workers, AI chat history.
create policy project_budgets_owner on public.project_budgets for all to authenticated
  using (private.is_project_owner(project_id)) with check (private.is_project_owner(project_id));
create policy budget_categories_owner on public.budget_categories for all to authenticated
  using (private.is_project_owner(project_id)) with check (private.is_project_owner(project_id));
create policy expenses_owner on public.expenses for all to authenticated
  using (private.is_project_owner(project_id)) with check (private.is_project_owner(project_id));
create policy workers_owner on public.workers for all to authenticated
  using (private.is_project_owner(project_id)) with check (private.is_project_owner(project_id));
create policy ai_chat_owner on public.ai_chat_messages for all to authenticated
  using (private.is_project_owner(project_id))
  with check (private.is_project_owner(project_id) and user_id = (select auth.uid()));

-- project_members: the owner manages grants (FR-04, UC-02 A2); a crew leader
-- can read only their own membership row (to know which screens to show).
create policy members_owner on public.project_members for all to authenticated
  using (private.is_project_owner(project_id))
  with check (private.is_project_owner(project_id) and user_id <> (select auth.uid()));
create policy members_select_self on public.project_members for select to authenticated
  using (user_id = (select auth.uid()));

-- stages: owner full access; crew leader reads only stages assigned to them.
create policy stages_owner on public.stages for all to authenticated
  using (private.is_project_owner(project_id)) with check (private.is_project_owner(project_id));
create policy stages_select_assigned on public.stages for select to authenticated
  using (private.is_assigned_stage(id));

-- stage_assignments: owner manages; crew leader reads their own assignments.
create policy assignments_owner on public.stage_assignments for all to authenticated
  using (private.is_project_owner(project_id)) with check (private.is_project_owner(project_id));
create policy assignments_select_self on public.stage_assignments for select to authenticated
  using (exists (select 1 from public.project_members m
                 where m.id = member_id and m.user_id = (select auth.uid())
                   and m.status = 'active'));

-- attendance_records: direct table access is owner-only, because rows contain
-- captured_rate (wage data). Crew leaders write via upsert_attendance() and
-- read via the attendance_sheet view, neither of which exposes rates.
create policy attendance_owner on public.attendance_records for all to authenticated
  using (private.is_project_owner(project_id)) with check (private.is_project_owner(project_id));

-- -----------------------------------------------------------------------------
-- 4. Restricted views for crew leaders (no wage rates, no phone numbers)
--    These run with the view owner's rights, so each one filters rows itself.
-- -----------------------------------------------------------------------------
create view public.worker_roster with (security_barrier = true) as
select w.id, w.project_id, w.full_name, w.trade, w.rate_type, w.is_active
from public.workers w
where w.is_active and private.has_permission(w.project_id, 'attendance');

create view public.attendance_sheet with (security_barrier = true) as
select a.id, a.project_id, a.worker_id, a.work_date, a.status, a.units, a.note
from public.attendance_records a
where private.has_permission(a.project_id, 'attendance');

-- -----------------------------------------------------------------------------
-- 5. RPC functions (called with supabase.rpc(); each checks its own permission)
-- -----------------------------------------------------------------------------

-- 5.1 Crew leader accepts an invitation after signing in from the invite link.
create or replace function public.accept_invitation(p_project_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.project_members
     set status = 'active', accepted_at = now()
   where project_id = p_project_id and user_id = (select auth.uid())
     and status = 'invited';
  if not found then
    raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0002';
  end if;
end $$;

-- 5.2 Record or correct attendance for one date (FR-19, UC-09 incl. A1 batch, A2 edit).
--     p_entries: [{"worker_id": uuid, "status": "full_day"|"half_day"|"absent"|"hourly",
--                  "hours": number (hourly only), "note": text}]
create or replace function public.upsert_attendance(
  p_project_id uuid, p_work_date date, p_entries jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  e        jsonb;
  v_status public.attendance_status;
  v_units  numeric(4,2);
  n        integer := 0;
begin
  if not private.has_permission(p_project_id, 'attendance') then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_work_date > (now() at time zone 'Asia/Ho_Chi_Minh')::date then
    raise exception 'FUTURE_DATE: attendance cannot be recorded for a future date'
      using errcode = 'P0001';
  end if;

  for e in select * from jsonb_array_elements(p_entries) loop
    v_status := (e ->> 'status')::public.attendance_status;
    v_units  := case v_status
                  when 'absent'   then 0
                  when 'half_day' then 0.5
                  when 'full_day' then 1
                  when 'hourly'   then (e ->> 'hours')::numeric
                end;

    -- rate_type_snapshot / captured_rate are filled by the trigger (BR-11);
    -- the placeholders below are overwritten.
    insert into public.attendance_records
      (project_id, worker_id, work_date, status, units,
       rate_type_snapshot, captured_rate, note, recorded_by)
    values
      (p_project_id, (e ->> 'worker_id')::uuid, p_work_date, v_status, v_units,
       'daily', 1, e ->> 'note', (select auth.uid()))
    on conflict (worker_id, work_date) do update
      set status = excluded.status, units = excluded.units,
          note = excluded.note, recorded_by = excluded.recorded_by
      where public.attendance_records.project_id = p_project_id;   -- no cross-project overwrite
    n := n + 1;
  end loop;
  return n;
end $$;

-- 5.3 Update progress of a stage (FR-16, UC-07 step 3). Only status, actual dates
--     and the progress note can change here; structure edits are owner-only via
--     the stages table (UC-07 E2).
create or replace function public.update_stage_progress(
  p_stage_id uuid, p_status public.stage_status,
  p_actual_start date, p_actual_end date, p_note text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_project uuid;
begin
  select project_id into v_project from public.stages where id = p_stage_id;
  if v_project is null
     or not (private.is_project_owner(v_project) or private.is_assigned_stage(p_stage_id)) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  update public.stages
     set status = p_status,
         actual_start_date = p_actual_start,
         actual_end_date = p_actual_end,
         progress_note = p_note
   where id = p_stage_id;
end $$;

-- 5.4 Save an AI stage draft after the owner confirms it (FR-14, BR-08).
--     All stages are inserted in one transaction or none are.
--     p_stages: [{"name": text, "planned_start_date": date, "planned_end_date": date}]
create or replace function public.confirm_stage_plan(p_project_id uuid, p_stages jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_next  integer;
  n       integer;
begin
  if not private.is_project_owner(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select coalesce(max(sequence_order), 0) into v_next
  from public.stages where project_id = p_project_id;

  insert into public.stages (project_id, name, sequence_order,
                             planned_start_date, planned_end_date)
  select p_project_id, s.value ->> 'name', v_next + s.ordinality::integer,
         (s.value ->> 'planned_start_date')::date,
         (s.value ->> 'planned_end_date')::date
  from jsonb_array_elements(p_stages) with ordinality as s(value, ordinality);
  get diagnostics n = row_count;
  return n;
end $$;

-- 5.5 Reorder stages atomically (FR-15). Uses the DEFERRABLE unique constraint.
create or replace function public.reorder_stages(p_project_id uuid, p_stage_ids uuid[])
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_project_owner(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if (select count(*) from public.stages where project_id = p_project_id)
     <> coalesce(array_length(p_stage_ids, 1), 0) then
    raise exception 'STAGE_LIST_MISMATCH' using errcode = 'P0001';
  end if;
  update public.stages s
     set sequence_order = t.ord
    from unnest(p_stage_ids) with ordinality as t(id, ord)
   where s.id = t.id and s.project_id = p_project_id;
end $$;

-- 5.6 Bounded, minimized project context for the AI Edge Function (FR-21, FR-22,
--     AD-04). Worker names and phone numbers are never selected; workers appear
--     as "Worker_NN (trade)". Called with the owner's JWT, so the owner check
--     applies. The Edge Function sanitizes again before calling Gemini.
create or replace function public.get_ai_project_context(p_project_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  ctx jsonb;
begin
  if not private.is_project_owner(p_project_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  with w as (
    select id, trade,
           'Worker_' || lpad(row_number() over (order by created_at, id)::text, 2, '0') as alias
    from public.workers where project_id = p_project_id
  )
  select jsonb_build_object(
    'project', (select jsonb_build_object(
                  'type', construction_type, 'floors', floor_count, 'area_m2', floor_area_m2,
                  'target_start', target_start_date, 'target_end', target_end_date)
                from public.projects where id = p_project_id),
    'budget', (select to_jsonb(s) - 'project_id'
               from public.v_project_financial_summary s where s.project_id = p_project_id),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object(
                     'name', name, 'planned', planned_amount, 'spent', actual_spent,
                     'state', threshold_state) order by sort_order), '[]'::jsonb)
                   from public.v_category_spending where project_id = p_project_id),
    'stages', (select coalesce(jsonb_agg(jsonb_build_object(
                 'order', sequence_order, 'name', name, 'status', status,
                 'planned_start', planned_start_date, 'planned_end', planned_end_date)
                 order by sequence_order), '[]'::jsonb)
               from public.stages where project_id = p_project_id),
    'recent_expenses', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                          select e.item_name, c.name as category, e.line_total, e.transaction_date
                          from public.expenses e
                          join public.budget_categories c on c.id = e.category_id
                          where e.project_id = p_project_id
                          order by e.transaction_date desc, e.created_at desc
                          limit 10) x),
    'labour_last_30_days', (select coalesce(jsonb_agg(jsonb_build_object(
                              'worker', w.alias || ' (' || w.trade || ')',
                              'units', t.units, 'estimated_wage', t.wage)), '[]'::jsonb)
                            from (select worker_id, sum(units) as units,
                                         sum(round(units * captured_rate))::bigint as wage
                                  from public.attendance_records
                                  where project_id = p_project_id
                                    and work_date >= (now() at time zone 'Asia/Ho_Chi_Minh')::date - 30
                                  group by worker_id) t
                            join w on w.id = t.worker_id),
    'recent_chat', (select coalesce(jsonb_agg(jsonb_build_object('role', role, 'content', content)
                      order by created_at), '[]'::jsonb)
                    from (select role, content, created_at from public.ai_chat_messages
                          where project_id = p_project_id
                          order by created_at desc limit 6) h)
  ) into ctx;
  return ctx;
end $$;

-- -----------------------------------------------------------------------------
-- 6. Privileges (Supabase grants table access to anon/authenticated by default;
--    RLS above does the filtering). Functions are not callable by anon.
-- -----------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on all tables in schema public from anon;
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.accept_invitation(uuid),
  public.upsert_attendance(uuid, date, jsonb),
  public.update_stage_progress(uuid, public.stage_status, date, date, text),
  public.confirm_stage_plan(uuid, jsonb),
  public.reorder_stages(uuid, uuid[]),
  public.get_ai_project_context(uuid)
to authenticated;
-- Trigger functions run as their definer/table owner; the views run the trigger-free
-- helpers in schema private, which authenticated may execute.
