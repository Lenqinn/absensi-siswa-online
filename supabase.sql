-- ABSENSI SISWA ONLINE — jalankan seluruh SQL ini di Supabase SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  student_code text not null unique,
  full_name text not null,
  class_level text not null check (class_level in ('X','XI','XII')),
  major text not null default 'TKJ',
  user_id uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  role text not null default 'student' check (role in ('admin','student')),
  student_id uuid unique references public.students(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  attendance_date date not null default (now() at time zone 'Asia/Jakarta')::date,
  attendance_time time not null default (now() at time zone 'Asia/Jakarta')::time,
  status text not null check (status in ('hadir','terlambat','izin')),
  reason text,
  created_at timestamptz not null default now(),
  unique(student_id, attendance_date),
  constraint reason_for_leave check (status <> 'izin' or (reason is not null and length(trim(reason)) > 0))
);
create table if not exists public.app_settings (
  id integer primary key check (id = 1),
  start_time time not null default '06:30',
  updated_at timestamptz not null default now()
);
insert into public.app_settings(id,start_time) values(1,'06:30') on conflict(id) do nothing;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $$;

-- Registration only reveals whether a code is available, not student details.
create or replace function public.student_code_available(p_code text) returns boolean
language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.students where student_code=trim(p_code) and user_id is null); $$;
grant execute on function public.student_code_available(text) to anon, authenticated;

-- New accounts are linked to a pre-created student code by a database trigger.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public
as $$
declare sid uuid; nm text; sc text;
begin
  nm := coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1));
  sc := trim(coalesce(new.raw_user_meta_data->>'student_code',''));
  if sc <> '' then
    select id into sid from public.students where student_code=sc and user_id is null for update;
    if sid is null then raise exception 'Kode siswa tidak valid atau sudah digunakan'; end if;
    update public.students set user_id=new.id where id=sid;
    insert into public.profiles(id,full_name,role,student_id) values(new.id,nm,'student',sid);
  else
    -- Accounts created without a student code get a student profile with no linked student.
    insert into public.profiles(id,full_name,role) values(new.id,nm,'student');
  end if;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Use server time for attendance and derive status on the database, not from the phone clock.
create or replace function public.submit_attendance(p_status text, p_reason text default null) returns public.attendance
language plpgsql security definer set search_path=public
as $$
declare sid uuid; start_at time; local_time time; local_date date; final_status text; result public.attendance;
begin
  select student_id into sid from public.profiles where id=auth.uid() and role='student';
  if sid is null then raise exception 'Akun siswa belum terhubung ke data siswa'; end if;
  select start_time into start_at from public.app_settings where id=1;
  local_time := (now() at time zone 'Asia/Jakarta')::time;
  local_date := (now() at time zone 'Asia/Jakarta')::date;
  if p_status='izin' then
    if length(trim(coalesce(p_reason,'')))=0 then raise exception 'Alasan izin wajib diisi'; end if;
    final_status := 'izin';
  elsif p_status='hadir' then
    final_status := case when local_time > start_at then 'terlambat' else 'hadir' end;
  else raise exception 'Status tidak valid'; end if;
  insert into public.attendance(student_id,attendance_date,attendance_time,status,reason)
  values(sid,local_date,local_time,final_status,case when final_status='izin' then trim(p_reason) else null end)
  on conflict(student_id,attendance_date) do update set attendance_time=excluded.attendance_time,status=excluded.status,reason=excluded.reason
  returning * into result;
  return result;
end; $$;
grant execute on function public.submit_attendance(text,text) to authenticated;

alter table public.students enable row level security;
alter table public.profiles enable row level security;
alter table public.attendance enable row level security;
alter table public.app_settings enable row level security;

drop policy if exists "Admin manages students" on public.students;
create policy "Admin manages students" on public.students for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Student reads own student record" on public.students;
create policy "Student reads own student record" on public.students for select to authenticated using (user_id=auth.uid());

drop policy if exists "Read own profile or admin reads all" on public.profiles;
create policy "Read own profile or admin reads all" on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
drop policy if exists "Admin updates profiles" on public.profiles;
create policy "Admin updates profiles" on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admin reads all attendance" on public.attendance;
create policy "Admin reads all attendance" on public.attendance for select to authenticated using (public.is_admin());
drop policy if exists "Student reads own attendance" on public.attendance;
create policy "Student reads own attendance" on public.attendance for select to authenticated using (student_id in (select student_id from public.profiles where id=auth.uid()));
-- Only the database function can write attendance, so clients cannot forge timestamps/status.

drop policy if exists "Authenticated reads settings" on public.app_settings;
create policy "Authenticated reads settings" on public.app_settings for select to authenticated using (true);
drop policy if exists "Admin manages settings" on public.app_settings;
create policy "Admin manages settings" on public.app_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Create the first account through Supabase Authentication, then promote it using the SQL below.
-- Replace EMAIL_ADMIN with the email used for the first admin account and run separately:
-- update public.profiles set role='admin' where id=(select id from auth.users where email='EMAIL_ADMIN');
