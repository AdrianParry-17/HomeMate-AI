-- Verification script for schema.sql + rls-policies.sql (run on a scratch database
-- after 00_supabase_shim.sql). Each check prints PASS or raises an error.
\set ON_ERROR_STOP on
\pset footer off

-- Test users: owner A, crew leader C (attendance + stages), crew D (attendance only),
-- unrelated user U.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'owner@test.vn', '{"full_name":"Owner A"}'),
  ('00000000-0000-0000-0000-00000000000c', 'crew.c@test.vn', '{"full_name":"Crew C"}'),
  ('00000000-0000-0000-0000-00000000000d', 'crew.d@test.vn', '{"full_name":"Crew D"}'),
  ('00000000-0000-0000-0000-0000000000ee', 'other@test.vn', '{}');

create or replace function pg_temp.as_user(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, false);
$$;
create or replace function pg_temp.ok(label text, cond boolean) returns text language plpgsql as $$
begin
  if not coalesce(cond, false) then raise exception 'FAIL: %', label; end if;
  return 'PASS  ' || label;
end $$;
-- expects the statement to fail; returns true when it did
create or replace function pg_temp.fails(stmt text) returns boolean language plpgsql as $$
begin
  execute stmt;
  return false;
exception when others then
  return true;
end $$;

-- number of rows a statement changed (0 = silently filtered by RLS)
create or replace function pg_temp.affected(stmt text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------- owner A
set role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');

select pg_temp.ok('profile auto-created by signup trigger',
  (select full_name from profiles where id = auth.uid()) = 'Owner A');

insert into projects (id, owner_id, name, construction_type, floor_count, floor_area_m2,
                      target_start_date, target_end_date)
values ('11111111-0000-0000-0000-000000000001', auth.uid(), 'Nha pho Q7', 'new_build', 3, 80,
        '2026-12-01', '2027-06-30');
insert into projects (owner_id, name, construction_type) values (auth.uid(), 'Sua bep', 'renovation');

select pg_temp.ok('AC-02 / BR-01: third active project is rejected',
  pg_temp.fails($$insert into projects (owner_id, name, construction_type)
                  values (auth.uid(), 'Du an 3', 'renovation')$$));

select pg_temp.ok('UC-03: four default categories seeded',
  (select count(*) from budget_categories
    where project_id = '11111111-0000-0000-0000-000000000001') = 4);

insert into project_budgets values ('11111111-0000-0000-0000-000000000001', 1000000000);
update budget_categories set planned_amount = 400000000 where name = 'Rough Construction';
update budget_categories set planned_amount = 10000000  where name = 'Finishing';

select pg_temp.ok('UC-03 E1: zero total budget rejected',
  pg_temp.fails($$update project_budgets set total_planned_amount = 0$$));

-- expenses
insert into expenses (project_id, category_id, item_name, quantity, unit, unit_price, transaction_date)
select '11111111-0000-0000-0000-000000000001', id, 'Xi mang Holcim PCB40', 100, 'bao', 95000, '2026-12-05'
from budget_categories where name = 'Rough Construction'
  and project_id = '11111111-0000-0000-0000-000000000001';
insert into expenses (project_id, category_id, item_name, quantity, unit, unit_price, transaction_date)
select '11111111-0000-0000-0000-000000000001', id, 'Cat xay', 2.5, 'm3', 333333, '2026-12-06'
from budget_categories where name = 'Rough Construction'
  and project_id = '11111111-0000-0000-0000-000000000001';
insert into expenses (project_id, category_id, item_name, quantity, unit, unit_price, transaction_date)
select '11111111-0000-0000-0000-000000000001', id, 'Gach men', 10, 'm2', 900000, '2026-12-07'
from budget_categories where name = 'Finishing'
  and project_id = '11111111-0000-0000-0000-000000000001';

select pg_temp.ok('FR-09 / NFR-06: line total = qty x price, rounded to 1 VND',
  (select line_total from expenses where item_name = 'Cat xay') = 833333);
select pg_temp.ok('BR-05: quantity <= 0 rejected',
  pg_temp.fails($$update expenses set quantity = 0 where item_name = 'Cat xay'$$));
select pg_temp.ok('BR-05: unit price <= 0 rejected',
  pg_temp.fails($$update expenses set unit_price = 0 where item_name = 'Cat xay'$$));
select pg_temp.ok('AC-04 / BR-06: Finishing at 90% -> warning',
  (select threshold_state from v_category_spending where name = 'Finishing'
     and project_id = '11111111-0000-0000-0000-000000000001') = 'warning');
insert into expenses (project_id, category_id, item_name, quantity, unit, unit_price, transaction_date)
select '11111111-0000-0000-0000-000000000001', id, 'Keo dan', 1, 'thung', 1000000, '2026-12-08'
from budget_categories where name = 'Finishing'
  and project_id = '11111111-0000-0000-0000-000000000001';
select pg_temp.ok('AC-04 / BR-06: Finishing at 100% -> reached',
  (select threshold_state from v_category_spending where name = 'Finishing'
     and project_id = '11111111-0000-0000-0000-000000000001') = 'reached');
select pg_temp.ok('UC-05 E1: empty category -> normal, no division by zero',
  (select threshold_state from v_category_spending where name = 'Contingency'
     and project_id = '11111111-0000-0000-0000-000000000001') = 'normal');
select pg_temp.ok('FR-10: remaining = planned - spent',
  (select remaining_balance from v_project_financial_summary
    where project_id = '11111111-0000-0000-0000-000000000001')
  = 1000000000 - (9500000 + 833333 + 9000000 + 1000000));

-- stages (AI draft confirmed atomically)
select pg_temp.ok('FR-14 / BR-08: confirm_stage_plan inserts all stages',
  public.confirm_stage_plan('11111111-0000-0000-0000-000000000001',
   '[{"name":"Mong","planned_start_date":"2026-12-01","planned_end_date":"2026-12-20"},
     {"name":"Phan tho","planned_start_date":"2026-12-21","planned_end_date":"2027-02-28"},
     {"name":"Hoan thien","planned_start_date":"2027-03-01","planned_end_date":"2027-06-30"}]') = 3);
select pg_temp.ok('BR-08: invalid draft (end < start) saves nothing',
  pg_temp.fails($$select public.confirm_stage_plan('11111111-0000-0000-0000-000000000001',
   '[{"name":"X","planned_start_date":"2027-07-01","planned_end_date":"2027-07-10"},
     {"name":"Y","planned_start_date":"2027-08-10","planned_end_date":"2027-08-01"}]')$$)
  and (select count(*) from stages where project_id = '11111111-0000-0000-0000-000000000001') = 3);
select public.reorder_stages('11111111-0000-0000-0000-000000000001',
  array(select id from stages where project_id = '11111111-0000-0000-0000-000000000001'
        order by sequence_order desc));
select pg_temp.ok('FR-15: reorder via deferrable unique constraint',
  (select name from stages where project_id = '11111111-0000-0000-0000-000000000001'
     and sequence_order = 1) = 'Hoan thien');
select pg_temp.ok('BR-07: stage end before start rejected',
  pg_temp.fails($$update stages set planned_end_date = '2026-11-01' where name = 'Mong'$$));

-- workers and crew leaders
insert into workers (id, project_id, full_name, phone, trade, rate_type, agreed_rate) values
 ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001',
  'Nguyen Van Tho', '0901234567', 'Mason', 'daily', 500000),
 ('22222222-0000-0000-0000-000000000002', '11111111-0000-0000-0000-000000000001',
  'Le Van Dien', '0912345678', 'Electrician', 'hourly', 80000);
select pg_temp.ok('FR-17 / BR-05: zero wage rate rejected',
  pg_temp.fails($$update workers set agreed_rate = 0 where trade = 'Mason'$$));

insert into project_members (id, project_id, user_id, can_record_attendance, can_update_assigned_stages) values
 ('33333333-0000-0000-0000-00000000000c', '11111111-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-00000000000c', true, true),
 ('33333333-0000-0000-0000-00000000000d', '11111111-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-00000000000d', true, false);
insert into stage_assignments (project_id, stage_id, member_id)
select project_id, id, '33333333-0000-0000-0000-00000000000c' from stages where name = 'Mong';

-- attendance: AC-07 (4 full days + 1 half day at 500,000 = 2,250,000)
select public.upsert_attendance('11111111-0000-0000-0000-000000000001', d::date,
  '[{"worker_id":"22222222-0000-0000-0000-000000000001","status":"full_day"}]')
from generate_series('2026-11-02'::date, '2026-11-05'::date, '1 day') d;
select public.upsert_attendance('11111111-0000-0000-0000-000000000001', '2026-11-06',
  '[{"worker_id":"22222222-0000-0000-0000-000000000001","status":"half_day"}]');
select pg_temp.ok('AC-07: 4 full + 1 half day at 500,000 = 2,250,000 VND',
  (select sum(estimated_wage) from v_attendance_wages
    where worker_id = '22222222-0000-0000-0000-000000000001') = 2250000);

update workers set agreed_rate = 600000 where id = '22222222-0000-0000-0000-000000000001';
select public.upsert_attendance('11111111-0000-0000-0000-000000000001', '2026-11-07',
  '[{"worker_id":"22222222-0000-0000-0000-000000000001","status":"full_day"}]');
select pg_temp.ok('BR-11: rate change affects only new records',
  (select sum(estimated_wage) from v_attendance_wages
    where worker_id = '22222222-0000-0000-0000-000000000001') = 2250000 + 600000);
with u as (update attendance_records set captured_rate = 1 where work_date = '2026-11-02'
           returning captured_rate)
select pg_temp.ok('BR-11: client cannot overwrite captured_rate',
  (select captured_rate from u) = 500000);

select pg_temp.ok('BR-09: hourly worker > 24h rejected',
  pg_temp.fails($$select public.upsert_attendance('11111111-0000-0000-0000-000000000001',
    '2026-11-03', '[{"worker_id":"22222222-0000-0000-0000-000000000002","status":"hourly","hours":25}]')$$));
select pg_temp.ok('BR-09: daily worker cannot be recorded in hours',
  pg_temp.fails($$select public.upsert_attendance('11111111-0000-0000-0000-000000000001',
    '2026-11-03', '[{"worker_id":"22222222-0000-0000-0000-000000000001","status":"hourly","hours":8}]')$$));
select public.upsert_attendance('11111111-0000-0000-0000-000000000001', '2026-11-03',
  '[{"worker_id":"22222222-0000-0000-0000-000000000002","status":"hourly","hours":7.5}]');
select public.upsert_attendance('11111111-0000-0000-0000-000000000001', '2026-11-03',
    '[{"worker_id":"22222222-0000-0000-0000-000000000002","status":"hourly","hours":8}]');
select pg_temp.ok('BR-10: second record same worker+date updates, not duplicates',
  (select count(*) from attendance_records
        where worker_id = '22222222-0000-0000-0000-000000000002' and work_date = '2026-11-03') = 1
  and (select units from attendance_records
        where worker_id = '22222222-0000-0000-0000-000000000002' and work_date = '2026-11-03') = 8);
select pg_temp.ok('BR-10: direct duplicate insert rejected by UNIQUE',
  pg_temp.fails($$insert into attendance_records (project_id, worker_id, work_date, status, units,
     rate_type_snapshot, captured_rate)
   values ('11111111-0000-0000-0000-000000000001','22222222-0000-0000-0000-000000000002',
           '2026-11-03','hourly',2,'hourly',1)$$));
select pg_temp.ok('UC-08 E2: hard delete of worker with attendance blocked',
  pg_temp.fails($$delete from workers where id = '22222222-0000-0000-0000-000000000001'$$));
update workers set is_active = false where id = '22222222-0000-0000-0000-000000000002';
select pg_temp.ok('FR-18: deactivated worker keeps history, gets no new attendance',
  (select count(*) from attendance_records where worker_id = '22222222-0000-0000-0000-000000000002') = 1
  and pg_temp.fails($$select public.upsert_attendance('11111111-0000-0000-0000-000000000001',
    '2026-11-04', '[{"worker_id":"22222222-0000-0000-0000-000000000002","status":"absent"}]')$$));
update workers set is_active = true where id = '22222222-0000-0000-0000-000000000002';

-- AI context: FR-22 / NFR-07 — no worker names or phone numbers
insert into ai_chat_messages (project_id, user_id, role, content)
values ('11111111-0000-0000-0000-000000000001', auth.uid(), 'user', 'Tien xi mang thang nay?');
select pg_temp.ok('FR-22 / NFR-07: AI context has aliases, no names/phones',
  (select c::text not like '%Nguyen Van Tho%' and c::text not like '%0901234567%'
          and c::text not like '%Le Van Dien%' and c::text like '%Worker_01 (Mason)%'
   from (select public.get_ai_project_context('11111111-0000-0000-0000-000000000001') c) x));

-- ---------------------------------------------------------------- crew C
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select pg_temp.ok('invited (not yet accepted) crew sees nothing',
  (select count(*) from projects) = 0 and (select count(*) from worker_roster) = 0);
select public.accept_invitation('11111111-0000-0000-0000-000000000001');
select pg_temp.ok('accepted crew reads project header', (select count(*) from projects) = 1);
select pg_temp.ok('AC-08 / BR-03: crew cannot read budget',
  (select count(*) from project_budgets) = 0 and (select count(*) from budget_categories) = 0
  and (select count(*) from v_project_financial_summary) = 0);
select pg_temp.ok('AC-08 / BR-03: crew cannot read expenses', (select count(*) from expenses) = 0);
select pg_temp.ok('BR-02: crew cannot read wage rates or phones (workers table hidden)',
  (select count(*) from workers) = 0 and (select count(*) from attendance_records) = 0);
select pg_temp.ok('crew reads roster without rate/phone columns',
  (select count(*) from worker_roster) = 2
  and not exists (select 1 from information_schema.columns
                  where table_name = 'worker_roster' and column_name in ('agreed_rate', 'phone')));
select pg_temp.ok('AC-08: crew with attendance permission records attendance',
  public.upsert_attendance('11111111-0000-0000-0000-000000000001', '2026-11-09',
   '[{"worker_id":"22222222-0000-0000-0000-000000000001","status":"full_day"}]') = 1);
select pg_temp.ok('crew reads attendance sheet without rates',
  (select count(*) from attendance_sheet) >= 7);
select pg_temp.ok('FR-16: crew sees only assigned stage', (select count(*) from stages) = 1);
select public.update_stage_progress((select id from stages where name = 'Mong'),
  'in_progress', '2026-12-02', null, 'Dao mong xong 50%');
select pg_temp.ok('FR-16: crew updates assigned stage progress',
  (select status from stages where name = 'Mong') = 'in_progress');
select pg_temp.ok('UC-07 E2: crew cannot update unassigned stage',
  pg_temp.fails($$select public.update_stage_progress(
     (select id from public.stages s where s.name = 'Phan tho'), 'completed', null, null, null)$$));
select pg_temp.ok('UC-07 E2: crew cannot rename/delete stages directly',
  pg_temp.affected($$update stages set name = 'Hacked'$$) = 0
  and pg_temp.affected($$delete from stages$$) = 0);
select pg_temp.ok('UC-08 E3: crew cannot change wage rates',
  pg_temp.affected($$update workers set agreed_rate = 1$$) = 0);
select pg_temp.ok('crew cannot read AI context', pg_temp.fails(
  $$select public.get_ai_project_context('11111111-0000-0000-0000-000000000001')$$));
select pg_temp.ok('crew cannot grant themselves permissions',
  pg_temp.affected($$update project_members set can_update_assigned_stages = true,
                       can_record_attendance = true$$) = 0);

-- ---------------------------------------------------------------- crew D (attendance only)
select pg_temp.as_user('00000000-0000-0000-0000-00000000000d');
select public.accept_invitation('11111111-0000-0000-0000-000000000001');
select pg_temp.ok('crew without stage permission sees no stages', (select count(*) from stages) = 0);

-- ---------------------------------------------------------------- owner revokes C
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
update project_members set status = 'revoked' where id = '33333333-0000-0000-0000-00000000000c';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000c');
select pg_temp.ok('UC-02 A2: revoked crew immediately loses access',
  (select count(*) from projects) = 0 and (select count(*) from worker_roster) = 0
  and pg_temp.fails($$select public.upsert_attendance('11111111-0000-0000-0000-000000000001',
    '2026-11-10', '[{"worker_id":"22222222-0000-0000-0000-000000000001","status":"full_day"}]')$$));

-- ---------------------------------------------------------------- unrelated user
select pg_temp.as_user('00000000-0000-0000-0000-0000000000ee');
select pg_temp.ok('NFR-03: unrelated user sees no project data',
  (select count(*) from projects) + (select count(*) from expenses)
  + (select count(*) from workers) + (select count(*) from stages)
  + (select count(*) from worker_roster) + (select count(*) from attendance_sheet)
  + (select count(*) from ai_chat_messages) = 0);
select pg_temp.ok('NFR-03: unrelated user cannot write into the project',
  pg_temp.fails($$insert into expenses (project_id, category_id, item_name, quantity, unit,
     unit_price, transaction_date)
   values ('11111111-0000-0000-0000-000000000001',
           (select id from budget_categories limit 1), 'x', 1, 'x', 1, '2026-12-01')$$));
select pg_temp.ok('UC-10 E2: unrelated user cannot pull AI context of another project',
  pg_temp.fails($$select public.get_ai_project_context('11111111-0000-0000-0000-000000000001')$$));

-- ---------------------------------------------------------------- anonymous
reset role;
set role anon;
select set_config('request.jwt.claims', '', false);
select pg_temp.ok('anon has no table access', pg_temp.fails($$select * from public.projects$$));
reset role;
