-- =====================================================================
-- Odbojka Brezovica (družinska različica): Supabase (PostgreSQL) shema in »API« funkcije
-- Poženi CELO datoteko v Supabase: SQL Editor > New query > Run.
-- Varno jo je pognati večkrat (ne prepiše podatkov).
--
-- Varnost: vse tabele so v shemi "app", ki je ZUNAJ API-ja (PostgREST jo ne izpostavi),
-- poleg tega imajo vklopljen RLS brez pravil. Odjemalec kliče samo funkcije api_* v shemi "public",
-- ki same preverijo družinsko kodo (neobvezno), prijavni žeton in pravice.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;
create schema if not exists app;

-- ---------- tabele ----------
create table if not exists app.settings (key text primary key, value text not null default '');
create table if not exists app.slots (
  id bigint generated always as identity primary key,
  team text not null, dow int not null check (dow between 0 and 6),
  from_t time not null, to_t time not null, place text not null default '',
  valid_from date, valid_until date, planned boolean not null default false);
create table if not exists app.changes (
  id bigint generated always as identity primary key,
  week date not null, team text not null, dow int not null, orig_from time,
  status text not null check (status in ('odpade','spremenjeno','dodano')),
  new_from time, new_to time, place text not null default '', note text not null default '',
  who text not null default '', at timestamptz not null default now());
create table if not exists app.matches (
  id bigint generated always as identity primary key,
  d date not null, team text not null, kind text not null, from_t time not null, to_t time not null,
  opponent text not null default '', place text not null default '', home_away text not null default '',
  note text not null default '', cancelled boolean not null default false,
  who text not null default '', at timestamptz not null default now());
create table if not exists app.holidays (
  id bigint generated always as identity primary key, from_d date not null, to_d date, note text not null default '');
create table if not exists app.players (
  id text primary key, name text not null, teams text[] not null, active boolean not null default true);
create table if not exists app.members (
  id text primary key, name text not null, role text not null check (role in ('starš','otrok')),
  teams text[] not null default '{}', pids text[] not null default '{}');
create table if not exists app.attendance (
  d date not null, team text not null, from_t time not null, player_id text not null,
  status text not null check (status in ('bil','ni bil','opravičen')),
  who text not null default '', at timestamptz not null default now(),
  primary key (d, team, from_t, player_id));
create table if not exists app.absences (
  id bigint generated always as identity primary key, player_id text not null,
  from_d date not null, to_d date not null, reason text not null, note text not null default '',
  who text not null default '', at timestamptz not null default now());
create table if not exists app.indiv (
  id bigint generated always as identity primary key, player_id text not null,
  d date not null, from_t time not null, to_t time not null, note text not null default '',
  who text not null default '', at timestamptz not null default now());
create table if not exists app.audit (
  id bigint generated always as identity primary key, at timestamptz not null default now(),
  who text not null default '', action text not null, details text not null default '');
create table if not exists app.tokens (
  token text primary key, role text not null, name text not null, mid text,
  pids text[] not null default '{}', teams text[] not null default '{}', expires timestamptz not null);
create table if not exists app.rate (key text primary key, n int not null default 0, since timestamptz not null default now());

do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname = 'app' loop
    execute format('alter table app.%I enable row level security', t);
  end loop;
end $$;

-- ---------- začetni podatki ----------
insert into app.settings(key, value) values ('sezona', '2026-09-01') on conflict (key) do nothing;
insert into app.slots (team, dow, from_t, to_t, place, valid_from, valid_until, planned)
select * from (values
  ('Starejši dečki', 0, '16:00'::time, '17:30'::time, 'Balon', null::date, null::date, false),
  ('Starejši dečki', 2, '15:00', '17:00', 'Balon', null, null, false),
  ('Starejši dečki', 3, '17:00', '19:00', 'Telovadnica OŠ Brezovica', null, null, false),
  ('Starejši dečki', 4, '15:00', '17:00', 'Balon', null, null, false),
  ('Kadeti', 1, '15:30', '17:30', 'Balon', null, null, false),
  ('Kadeti', 2, '17:00', '18:30', 'Balon', null, null, false),
  ('Kadeti', 3, '15:30', '17:30', 'Balon', null, '2026-11-09'::date, false),
  ('Kadeti', 4, '17:00', '18:30', 'Balon', null, null, false),
  ('Kadeti', 0, '16:30', '18:00', 'Telovadnica OŠ Brezovica', '2026-11-09'::date, null, true),
  ('Mladinci', 0, '16:30', '18:00', 'Telovadnica OŠ Brezovica', null, '2026-11-09'::date, false),
  ('Mladinci', 1, '16:30', '18:30', 'Telovadnica OŠ Brezovica', null, null, false),
  ('Mladinci', 2, '18:30', '20:00', 'Balon', null, null, false),
  ('Mladinci', 4, '16:30', '18:30', 'Telovadnica OŠ Brezovica', null, null, false),
  ('Mladinci', 3, '15:30', '17:30', 'Balon', '2026-11-09'::date, null, true)
) v(team, dow, from_t, to_t, place, valid_from, valid_until, planned)
where not exists (select 1 from app.slots);

-- Družina: Lado in Tina (starša, vidita vse ekipe), Val (Mladinci), Tim (Kadeti, Starejši dečki; primarna ekipa je prva).
insert into app.players(id, name, teams, active) values
  ('p_val', 'Val', '{Mladinci}', true), ('p_tim', 'Tim', '{Kadeti,"Starejši dečki"}', true)
on conflict (id) do nothing;
insert into app.members(id, name, role, teams, pids) values
  ('m1', 'Lado', 'starš', '{}', '{}'), ('m2', 'Tina', 'starš', '{}', '{}'),
  ('m3', 'Val', 'otrok', '{Mladinci}', '{p_val}'), ('m4', 'Tim', 'otrok', '{"Starejši dečki",Kadeti}', '{p_tim}')
on conflict (id) do nothing;
-- Timove odsotnosti: priprave reprezentance U-16 in MEVZA (samo če jih še ni).
insert into app.absences(player_id, from_d, to_d, reason, note, who)
select 'p_tim', v.a::date, v.b::date, 'Reprezentanca', 'Reprezentanca U-16 priprave', 'uvoz'
from (values ('2026-11-09','2026-11-09'), ('2026-11-22','2026-11-26'), ('2026-12-07','2026-12-08'),
             ('2026-12-21','2026-12-24'), ('2026-12-27','2026-12-30'), ('2027-01-01','2027-01-10')) v(a, b)
where not exists (select 1 from app.absences x where x.player_id = 'p_tim' and x.from_d = v.a::date and x.to_d = v.b::date);

-- ---------- pomožne funkcije (shema app, ni dostopna iz API-ja) ----------
create or replace function app.version() returns text language sql immutable as $fn$ select 'S1 · Supabase' $fn$;
create or replace function app.days() returns text[] language sql immutable as $fn$ select array['Pon','Tor','Sre','Čet','Pet','Sob','Ned'] $fn$;
create or replace function app.teams_all() returns text[] language sql immutable as $fn$ select array['Starejši dečki','Kadeti','Mladinci'] $fn$;
create or replace function app.abs_reasons() returns text[] language sql immutable as $fn$ select array['Reprezentanca','Bolezen','Poškodba','Družinsko / počitnice','Šola','Drugo'] $fn$;
create or replace function app.tz_today() returns date language sql stable as $fn$ select (now() at time zone 'Europe/Ljubljana')::date $fn$;
create or replace function app.setting(k text) returns text language sql stable as $fn$ select value from app.settings where key = k $fn$;
create or replace function app.hh(t time) returns text language sql immutable as $fn$ select to_char(t, 'HH24:MI') $fn$;
create or replace function app.dd(d date) returns text language sql immutable as $fn$ select coalesce(to_char(d, 'YYYY-MM-DD'), '') $fn$;
create or replace function app.fmt_ts(t timestamptz) returns text language sql stable as $fn$
  select to_char(t at time zone 'Europe/Ljubljana', 'FMDD. FMMM. YYYY HH24:MI') $fn$;
create or replace function app.dow_of(d date) returns int language sql immutable as $fn$ select extract(isodow from d)::int - 1 $fn$;
create or replace function app.monday(d date) returns date language sql immutable as $fn$ select d - (extract(isodow from d)::int - 1) $fn$;
create or replace function app.clean(v text, mx int) returns text language sql immutable as $fn$ select left(btrim(coalesce(v, '')), mx) $fn$;

create or replace function app.chk_team(t text) returns text language plpgsql immutable as $fn$
begin
  if t is null or not (t = any(app.teams_all())) then raise exception 'Neveljavna vrednost: %', coalesce(t, ''); end if;
  return t;
end $fn$;
create or replace function app.chk_date(v text) returns date language plpgsql immutable as $fn$
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Neveljaven datum.'; end if;
  begin return v::date; exception when others then raise exception 'Neveljaven datum.'; end;
end $fn$;
create or replace function app.chk_time(v text) returns time language plpgsql immutable as $fn$
begin
  if v is null or v !~ '^\d{1,2}:\d{2}$' then raise exception 'Neveljavna ura.'; end if;
  begin return v::time; exception when others then raise exception 'Neveljavna ura.'; end;
end $fn$;
create or replace function app.day_idx(p text) returns int language plpgsql immutable as $fn$
declare i int := array_position(app.days(), p);
begin
  if i is null then raise exception 'Neveljavna vrednost: %', coalesce(p, ''); end if;
  return i - 1;
end $fn$;
create or replace function app.new_id(prefix text) returns text language sql volatile as $fn$
  select prefix || to_hex((extract(epoch from clock_timestamp()) * 1000)::bigint) || substr(md5(random()::text), 1, 3) $fn$;

create or replace function app.log_it(s app.tokens, a text, d text) returns void language sql as $fn$
  insert into app.audit(who, action, details) values (s.name, a, left(coalesce(d, ''), 300)) $fn$;

create or replace function app.sess(p_token text) returns app.tokens language plpgsql as $fn$
declare s app.tokens;
begin
  select * into s from app.tokens where token = p_token and expires > now();
  if not found then raise exception 'Seja je potekla. Prijavi se ponovno.'; end if;
  return s;
end $fn$;
-- Starš (role 'trener'): vse. Otrok: odpovedi, tekme, prisotnost svojih igralcev.
create or replace function app.need_editor(p_token text) returns app.tokens language plpgsql as $fn$
declare s app.tokens := app.sess(p_token);
begin
  if s.role not in ('trener', 'otrok') then raise exception 'Tega ne moreš storiti.'; end if;
  return s;
end $fn$;
create or replace function app.need_coach(p_token text) returns app.tokens language plpgsql as $fn$
declare s app.tokens := app.sess(p_token);
begin
  if s.role <> 'trener' then raise exception 'To lahko stori samo starš.'; end if;
  return s;
end $fn$;
-- Igralec pripada otroku, če se ujema ID ali je prvo ime igralca enako imenu člana (npr. »Tim Modic« = član »Tim«).
create or replace function app.can_edit_player(s app.tokens, pl app.players) returns boolean language sql stable as $fn$
  select s.role = 'trener' or (s.role = 'otrok' and (pl.id = any(coalesce(s.pids, '{}'::text[]))
          or lower(split_part(btrim(pl.name), ' ', 1)) = lower(btrim(s.name)))) $fn$;
create or replace function app.need_player(p_token text, p_pid text) returns app.players language plpgsql as $fn$
declare s app.tokens := app.sess(p_token); pl app.players;
begin
  select * into pl from app.players where id = p_pid;
  if not found then raise exception 'Igralca ni mogoče najti. Osveži stran.'; end if;
  if not app.can_edit_player(s, pl) then raise exception 'Za tega igralca nimaš pravic.'; end if;
  return pl;
end $fn$;

-- =====================================================================
-- API funkcije (public): enako ime in vrstni red parametrov kot prej v Apps Script
-- =====================================================================

-- ---------- javno branje (z družinsko kodo, če je nastavljena) ----------
create or replace function public.api_get_data(p_code text) returns jsonb language plpgsql security definer
set search_path = app, public, extensions as $fn$
declare fh text := app.setting('family_code_hash'); r app.rate;
begin
  if fh is not null and fh <> '' then
    select * into r from app.rate where key = 'code';
    if found and r.since < now() - interval '15 minutes' then update app.rate set n = 0, since = now() where key = 'code'; r.n := 0; end if;
    if coalesce(r.n, 0) >= 20 then return jsonb_build_object('locked', true, 'napaka', 'Preveč neuspelih poskusov. Poskusi znova čez 15 minut.'); end if;
    if coalesce(p_code, '') = '' then return jsonb_build_object('locked', true); end if;
    if extensions.crypt(p_code, fh) <> fh then
      insert into app.rate(key, n, since) values ('code', 1, now()) on conflict (key) do update set n = app.rate.n + 1;
      return jsonb_build_object('locked', true, 'napaka', 'Napačna koda.');
    end if;
    delete from app.rate where key = 'code';
  end if;
  return jsonb_build_object(
    'termini', coalesce((select jsonb_agg(jsonb_build_array(s.team, (app.days())[s.dow + 1], app.hh(s.from_t), app.hh(s.to_t), s.place,
                app.dd(s.valid_from), app.dd(s.valid_until), case when s.planned then 'da' else '' end, s.id::text) order by s.id) from app.slots s), '[]'::jsonb),
    'spremembe', coalesce((select jsonb_agg(jsonb_build_array(app.dd(c.week), c.team, (app.days())[c.dow + 1], coalesce(app.hh(c.orig_from), ''), c.status,
                coalesce(app.hh(c.new_from), ''), coalesce(app.hh(c.new_to), ''), c.place, c.note, c.who, app.fmt_ts(c.at)) order by c.id) from app.changes c), '[]'::jsonb),
    'tekme', coalesce((select jsonb_agg(jsonb_build_array(app.dd(m.d), m.team, m.kind, app.hh(m.from_t), app.hh(m.to_t), m.opponent, m.place, m.home_away, m.note,
                case when m.cancelled then 'odpade' else '' end, m.who, app.fmt_ts(m.at), m.id::text) order by m.d, m.id) from app.matches m), '[]'::jsonb),
    'pocitnice', coalesce((select jsonb_agg(jsonb_build_array(app.dd(h.from_d), app.dd(h.to_d), h.note) order by h.from_d) from app.holidays h), '[]'::jsonb),
    'sezona', coalesce(app.setting('sezona'), '2026-09-01'),
    'clani', coalesce((select jsonb_agg(jsonb_build_array(b.id, b.name, b.role,
                case when b.role = 'starš' or cardinality(b.teams) = 0 or b.teams @> app.teams_all() then 'vse' else array_to_string(b.teams, ', ') end,
                array_to_string(b.pids, ', ')) order by b.id) from app.members b), '[]'::jsonb),
    'nacin', 'druzina', 'zascita', false, 'posodobljeno', app.fmt_ts(now()), 'verzija', app.version());
end $fn$;

-- ---------- vstop (»kdo si«) ----------
create or replace function public.api_enter(p_id text, p_code text) returns jsonb language plpgsql security definer
set search_path = app, public, extensions as $fn$
declare m app.members; fh text := app.setting('family_code_hash'); r app.rate; tok text; v_role text;
begin
  delete from app.tokens where expires < now();
  if fh is not null and fh <> '' then
    select * into r from app.rate where key = 'code';
    if found and r.since < now() - interval '15 minutes' then update app.rate set n = 0, since = now() where key = 'code'; r.n := 0; end if;
    if coalesce(r.n, 0) >= 20 then return jsonb_build_object('error', 'Preveč neuspelih poskusov. Poskusi znova čez 15 minut.'); end if;
    if extensions.crypt(coalesce(p_code, ''), fh) <> fh then
      if coalesce(p_code, '') <> '' then insert into app.rate(key, n, since) values ('code', 1, now()) on conflict (key) do update set n = app.rate.n + 1; end if;
      return jsonb_build_object('error', 'Napačna družinska koda.');
    end if;
  end if;
  select * into m from app.members where id = coalesce(p_id, '');
  if not found then return jsonb_build_object('error', 'Neznan član.'); end if;
  v_role := case when m.role = 'starš' then 'trener' else 'otrok' end;
  tok := encode(extensions.gen_random_bytes(24), 'hex');
  insert into app.tokens(token, role, name, mid, pids, teams, expires)
  values (tok, v_role, m.name, m.id, m.pids, case when m.role = 'starš' or cardinality(m.teams) = 0 then app.teams_all() else m.teams end, now() + interval '6 hours');
  return jsonb_build_object('token', tok, 'role', v_role, 'oz', '', 'mid', m.id);
end $fn$;

create or replace function public.api_logout(p_token text) returns boolean language plpgsql security definer
set search_path = app, public, extensions as $fn$
begin delete from app.tokens where token = p_token; return true; end $fn$;

-- Družinska koda: prazno = brez kode. Samo starš.
create or replace function public.api_set_family_code(p_token text, p_code text) returns boolean language plpgsql security definer
set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_coach(p_token); v text := btrim(coalesce(p_code, ''));
begin
  if v = '' then
    delete from app.settings where key = 'family_code_hash';
  else
    if length(v) < 6 then raise exception 'Koda naj ima vsaj 6 znakov.'; end if;
    insert into app.settings(key, value) values ('family_code_hash', extensions.crypt(v, extensions.gen_salt('bf')))
    on conflict (key) do update set value = excluded.value;
  end if;
  perform app.log_it(s, case when v = '' then 'Odstranjena družinska koda' else 'Nastavljena družinska koda' end, '');
  return true;
end $fn$;

-- ---------- zasebni podatki po vstopu ----------
create or replace function public.api_get_private(p_token text) returns jsonb language plpgsql stable security definer
set search_path = app, public, extensions as $fn$
declare s app.tokens := app.sess(p_token);
begin
  return jsonb_build_object('role', s.role, 'oz', '',
    'igralci', coalesce((select jsonb_agg(jsonb_build_array(p.id, p.name, array_to_string(p.teams, ', '), case when p.active then 'da' else 'ne' end, '', p.id) order by p.name)
                         from app.players p where app.can_edit_player(s, p)), '[]'::jsonb),
    'prisotnost', coalesce((select jsonb_agg(jsonb_build_array(app.dd(a.d), a.team, app.hh(a.from_t), a.player_id, a.status, a.who, app.fmt_ts(a.at)))
                            from app.attendance a join app.players p on p.id = a.player_id where app.can_edit_player(s, p)), '[]'::jsonb),
    'odsotnosti', coalesce((select jsonb_agg(jsonb_build_array(b.player_id, app.dd(b.from_d), app.dd(b.to_d), b.reason, b.note, b.who, app.fmt_ts(b.at), b.id::text) order by b.from_d)
                            from app.absences b join app.players p on p.id = b.player_id where app.can_edit_player(s, p)), '[]'::jsonb),
    'individualni', coalesce((select jsonb_agg(jsonb_build_array(i.player_id, app.dd(i.d), app.hh(i.from_t), app.hh(i.to_t), i.note, i.who, app.fmt_ts(i.at), i.id::text) order by i.d)
                              from app.indiv i join app.players p on p.id = i.player_id where app.can_edit_player(s, p)), '[]'::jsonb),
    'razlogi', to_jsonb(app.abs_reasons()));
end $fn$;

create or replace function public.api_get_log(p_token text) returns jsonb language plpgsql stable security definer
set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_coach(p_token);
begin
  return coalesce((select jsonb_agg(jsonb_build_array(app.fmt_ts(x.at), x.who, x.action, x.details) order by x.id desc)
                   from (select * from app.audit order by id desc limit 60) x), '[]'::jsonb);
end $fn$;

-- ---------- igralci (samo starš) ----------
create or replace function public.api_save_player(p_token text, p_p jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_coach(p_token); v_name text := app.clean(p_p->>'name', 60); v_teams text[]; v_id text := coalesce(p_p->>'id', ''); v_ex boolean;
begin
  if v_name = '' then raise exception 'Vpiši ime igralca.'; end if;
  select coalesce(array_agg(app.chk_team(x)), '{}'::text[]) into v_teams from jsonb_array_elements_text(coalesce(p_p->'teams', '[]'::jsonb)) x;
  if cardinality(v_teams) = 0 then raise exception 'Izberi vsaj eno ekipo.'; end if;
  v_ex := exists (select 1 from app.players where id = v_id);
  if v_ex then
    update app.players set name = v_name, teams = v_teams, active = coalesce((p_p->>'active')::boolean, true) where id = v_id;
  else
    insert into app.players(id, name, teams, active) values (app.new_id('p'), v_name, v_teams, coalesce((p_p->>'active')::boolean, true));
  end if;
  perform app.log_it(s, case when v_ex then 'Urejen igralec' else 'Dodan igralec' end, v_name || ' · ' || array_to_string(v_teams, ', '));
  return true;
end $fn$;

-- Trajen izbris igralca. Zapisi prisotnosti, odsotnosti in individualnih treningov ostanejo v bazi, a se ne prikazujejo.
create or replace function public.api_delete_player(p_token text, p_id text)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_coach(p_token); v_name text;
begin
  select name into v_name from app.players where id = p_id;
  if not found then raise exception 'Igralca ni mogoče najti. Osveži stran.'; end if;
  delete from app.players where id = p_id;
  perform app.log_it(s, 'Izbrisan igralec', v_name);
  return true;
end $fn$;

-- ---------- prisotnost ----------
-- entries: [{id, status}], status '' pobriše vnos. Otrok lahko beleži samo svoje igralce. Vnos vnaprej ni mogoč.
create or replace function public.api_save_attendance(p_token text, p_date text, p_team text, p_from text, p_entries jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); v_d date := app.chk_date(p_date); v_tm time := app.chk_time(p_from);
        e jsonb; v_id text; v_st text; pl app.players;
begin
  p_team := app.chk_team(p_team);
  if v_d > app.tz_today() then raise exception 'Prisotnosti ni mogoče vnesti vnaprej.'; end if;
  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) > 80 then raise exception 'Neveljavni podatki.'; end if;
  for e in select * from jsonb_array_elements(p_entries) loop
    v_id := coalesce(e->>'id', ''); v_st := coalesce(e->>'status', '');
    select * into pl from app.players where id = v_id;
    if not found or not (p_team = any(pl.teams)) or not app.can_edit_player(s, pl) then continue; end if;
    if v_st <> '' and v_st not in ('bil', 'ni bil', 'opravičen') then raise exception 'Neveljaven status.'; end if;
    if v_st = '' then
      delete from app.attendance a where a.d = v_d and a.team = p_team and a.from_t = v_tm and a.player_id = v_id;
    else
      insert into app.attendance(d, team, from_t, player_id, status, who, at) values (v_d, p_team, v_tm, v_id, v_st, s.name, now())
      on conflict (d, team, from_t, player_id) do update set status = excluded.status, who = excluded.who, at = now();
    end if;
  end loop;
  return true;
end $fn$;

-- ---------- odpovedi in spremembe treningov (starš ali otrok) ----------
create or replace function public.api_set_cancel_training(p_token text, p_week text, p_team text, p_day text, p_orig_from text, p_cancel boolean, p_note text)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); v_week date := app.chk_date(p_week); v_dow int := app.day_idx(p_day); v_orig time := app.chk_time(p_orig_from);
        v_note text := app.clean(p_note, 200); c app.changes;
begin
  p_team := app.chk_team(p_team);
  select * into c from app.changes x where x.week = v_week and x.team = p_team and x.dow = v_dow and x.orig_from = v_orig and x.status <> 'dodano' order by x.id desc limit 1;
  if p_cancel then
    if found then
      update app.changes set status = 'odpade', note = case when v_note <> '' then v_note else note end, who = s.name, at = now() where id = c.id;
    else
      insert into app.changes(week, team, dow, orig_from, status, note, who) values (v_week, p_team, v_dow, v_orig, 'odpade', v_note, s.name);
    end if;
  elsif found then
    if c.new_from is not null or c.new_to is not null or c.place <> '' then update app.changes set status = 'spremenjeno', who = s.name, at = now() where id = c.id;
    else delete from app.changes where id = c.id; end if;
  end if;
  perform app.log_it(s, case when p_cancel then 'Odpoved treninga' else 'Povrnitev treninga' end,
                     p_team || ' ' || p_day || ' ' || p_orig_from || ' (teden ' || p_week || ')' || case when v_note <> '' then ' · ' || v_note else '' end);
  return true;
end $fn$;

create or replace function public.api_edit_training_week(p_token text, p_week text, p_team text, p_day text, p_orig_from text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); v_week date := app.chk_date(p_week); v_dow int := app.day_idx(p_day); v_orig time := app.chk_time(p_orig_from);
        v_from time := app.chk_time(p_m->>'from'); v_to time := app.chk_time(p_m->>'to'); c app.changes;
begin
  p_team := app.chk_team(p_team);
  if v_from >= v_to then raise exception 'Konec mora biti poznejši od začetka.'; end if;
  select * into c from app.changes x where x.week = v_week and x.team = p_team and x.dow = v_dow and x.orig_from = v_orig and x.status <> 'dodano' order by x.id desc limit 1;
  if found then
    update app.changes set status = case when c.status = 'odpade' then 'odpade' else 'spremenjeno' end, new_from = v_from, new_to = v_to,
           place = app.clean(p_m->>'place', 80), note = app.clean(p_m->>'note', 200), who = s.name, at = now() where id = c.id;
  else
    insert into app.changes(week, team, dow, orig_from, status, new_from, new_to, place, note, who)
    values (v_week, p_team, v_dow, v_orig, 'spremenjeno', v_from, v_to, app.clean(p_m->>'place', 80), app.clean(p_m->>'note', 200), s.name);
  end if;
  perform app.log_it(s, 'Sprememba treninga v tednu', p_team || ' ' || p_day || ' ' || p_orig_from || ' → ' || (p_m->>'from') || '–' || (p_m->>'to') || ' (teden ' || p_week || ')');
  return true;
end $fn$;

create or replace function public.api_reset_training_week(p_token text, p_week text, p_team text, p_day text, p_orig_from text)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); v_week date := app.chk_date(p_week); v_dow int := app.day_idx(p_day); v_orig time := app.chk_time(p_orig_from); c app.changes;
begin
  p_team := app.chk_team(p_team);
  select * into c from app.changes x where x.week = v_week and x.team = p_team and x.dow = v_dow and x.orig_from = v_orig and x.status <> 'dodano' order by x.id desc limit 1;
  if not found then return true; end if;
  if c.status = 'odpade' then update app.changes set new_from = null, new_to = null, place = '' where id = c.id; else delete from app.changes where id = c.id; end if;
  perform app.log_it(s, 'Ponastavitev treninga v tednu', p_team || ' ' || p_day || ' ' || p_orig_from || ' (teden ' || p_week || ')');
  return true;
end $fn$;

create or replace function public.api_add_extra_training(p_token text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); v_team text := app.chk_team(p_m->>'team');
        v_d date := app.chk_date(p_m->>'date'); v_from time := app.chk_time(p_m->>'from'); v_to time := app.chk_time(p_m->>'to');
begin
  if v_from >= v_to then raise exception 'Konec mora biti poznejši od začetka.'; end if;
  if s.role = 'otrok' and not (v_team = any(s.teams)) then raise exception 'Te ekipe ne moreš urejati.'; end if;
  insert into app.changes(week, team, dow, orig_from, status, new_from, new_to, place, note, who)
  values (app.monday(v_d), v_team, app.dow_of(v_d), null, 'dodano', v_from, v_to, app.clean(p_m->>'place', 80), app.clean(p_m->>'note', 200), s.name);
  perform app.log_it(s, 'Dodan izredni trening', v_team || ' · ' || app.dd(v_d) || ' ' || app.hh(v_from) || '–' || app.hh(v_to));
  return true;
end $fn$;

-- ---------- tekme ----------
create or replace function public.api_add_match(p_token text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); v_team text := app.chk_team(p_m->>'team');
        v_d date := app.chk_date(p_m->>'date'); v_from time := app.chk_time(p_m->>'from'); v_to time := app.chk_time(p_m->>'to'); v_kind text := p_m->>'type'; v_ha text := coalesce(p_m->>'homeAway', '');
begin
  if v_kind is null or v_kind not in ('Trening tekma', 'OZS tekma') then raise exception 'Neveljavna vrednost: %', coalesce(v_kind, ''); end if;
  if v_ha not in ('', 'Doma', 'Gostje') then raise exception 'Neveljavna vrednost: %', v_ha; end if;
  if v_from >= v_to then raise exception 'Konec mora biti poznejši od začetka.'; end if;
  insert into app.matches(d, team, kind, from_t, to_t, opponent, place, home_away, note, who)
  values (v_d, v_team, v_kind, v_from, v_to, app.clean(p_m->>'opponent', 80), app.clean(p_m->>'place', 80), v_ha, app.clean(p_m->>'note', 200), s.name);
  perform app.log_it(s, 'Dodana tekma', v_team || ' · ' || v_kind || ' · ' || app.dd(v_d) || ' ' || app.hh(v_from) || case when coalesce(p_m->>'opponent', '') <> '' then ' vs ' || (p_m->>'opponent') else '' end);
  return true;
end $fn$;

create or replace function public.api_update_match(p_token text, p_row text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); r app.matches; v_team text := app.chk_team(p_m->>'team'); v_d date := app.chk_date(p_m->>'date');
        v_from time := app.chk_time(p_m->>'from'); v_to time := app.chk_time(p_m->>'to'); v_kind text := p_m->>'type'; v_ha text := coalesce(p_m->>'homeAway', '');
begin
  select * into r from app.matches where id = p_row::bigint;
  if not found then raise exception 'Tekme ni mogoče najti. Osveži stran.'; end if;
  if v_kind is null or v_kind not in ('Trening tekma', 'OZS tekma') then raise exception 'Neveljavna vrednost: %', coalesce(v_kind, ''); end if;
  if v_ha not in ('', 'Doma', 'Gostje') then raise exception 'Neveljavna vrednost: %', v_ha; end if;
  if v_from >= v_to then raise exception 'Konec mora biti poznejši od začetka.'; end if;
  update app.matches set d = v_d, team = v_team, kind = v_kind, from_t = v_from, to_t = v_to, opponent = app.clean(p_m->>'opponent', 80),
         place = app.clean(p_m->>'place', 80), home_away = v_ha, note = app.clean(p_m->>'note', 200), who = s.name, at = now() where id = r.id;
  perform app.log_it(s, 'Urejena tekma', v_team || ' · ' || v_kind || ' · ' || app.dd(v_d) || ' ' || app.hh(v_from));
  return true;
end $fn$;

create or replace function public.api_delete_match(p_token text, p_row text)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); r app.matches;
begin
  select * into r from app.matches where id = p_row::bigint;
  if not found then raise exception 'Tekme ni mogoče najti. Osveži stran.'; end if;
  delete from app.matches where id = r.id;
  perform app.log_it(s, 'Izbrisana tekma', r.team || ' · ' || r.kind || ' · ' || app.dd(r.d) || ' ' || app.hh(r.from_t));
  return true;
end $fn$;

create or replace function public.api_set_cancel_match(p_token text, p_row text, p_cancel boolean)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_editor(p_token); r app.matches;
begin
  select * into r from app.matches where id = p_row::bigint;
  if not found then raise exception 'Tekme ni mogoče najti. Osveži stran.'; end if;
  update app.matches set cancelled = coalesce(p_cancel, false), who = s.name, at = now() where id = r.id;
  perform app.log_it(s, case when p_cancel then 'Odpoved tekme' else 'Povrnitev tekme' end, r.team || ' · ' || r.kind || ' · ' || app.dd(r.d) || ' ' || app.hh(r.from_t));
  return true;
end $fn$;

-- ---------- redni termini (samo starš) ----------
create or replace function public.api_change_slot(p_token text, p_row text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_coach(p_token); sl app.slots; v_eff date := app.chk_date(p_m->>'effective'); v_dow int := app.day_idx(p_m->>'day');
        v_from time := app.chk_time(p_m->>'from'); v_to time := app.chk_time(p_m->>'to'); v_place text := app.clean(p_m->>'place', 80); v_pl boolean := coalesce((p_m->>'planned')::boolean, false);
begin
  select * into sl from app.slots where id = p_row::bigint;
  if not found then raise exception 'Termina ni mogoče najti. Osveži stran.'; end if;
  if v_from >= v_to then raise exception 'Konec mora biti poznejši od začetka.'; end if;
  if sl.valid_until is not null and sl.valid_until <= v_eff then raise exception 'Ta termin se je že iztekel.'; end if;
  if sl.valid_from is not null and sl.valid_from >= v_eff then
    update app.slots set dow = v_dow, from_t = v_from, to_t = v_to, place = v_place, valid_from = v_eff, planned = v_pl where id = sl.id;
  else
    update app.slots set valid_until = v_eff where id = sl.id;
    insert into app.slots(team, dow, from_t, to_t, place, valid_from, valid_until, planned) values (sl.team, v_dow, v_from, v_to, v_place, v_eff, sl.valid_until, v_pl);
  end if;
  perform app.log_it(s, 'Sprememba rednega termina', sl.team || ': ' || (app.days())[sl.dow + 1] || ' ' || app.hh(sl.from_t) || '–' || app.hh(sl.to_t) || ' → ' || (app.days())[v_dow + 1] || ' ' || app.hh(v_from) || '–' || app.hh(v_to) || ' od ' || app.dd(v_eff));
  return true;
end $fn$;

create or replace function public.api_end_slot(p_token text, p_row text, p_date text)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_coach(p_token); sl app.slots; v_d date := app.chk_date(p_date);
begin
  select * into sl from app.slots where id = p_row::bigint;
  if not found then raise exception 'Termina ni mogoče najti. Osveži stran.'; end if;
  if sl.valid_from is not null and v_d <= sl.valid_from then raise exception 'Datum mora biti po začetku veljavnosti.'; end if;
  update app.slots set valid_until = v_d where id = sl.id;
  perform app.log_it(s, 'Zaključen redni termin', sl.team || ': ' || (app.days())[sl.dow + 1] || ' ' || app.hh(sl.from_t) || '–' || app.hh(sl.to_t) || ' do ' || app.dd(v_d));
  return true;
end $fn$;

create or replace function public.api_add_slot(p_token text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.need_coach(p_token); v_team text := app.chk_team(p_m->>'team'); v_dow int := app.day_idx(p_m->>'day');
        v_from time := app.chk_time(p_m->>'from'); v_to time := app.chk_time(p_m->>'to'); v_since date := app.chk_date(p_m->>'since');
begin
  if v_from >= v_to then raise exception 'Konec mora biti poznejši od začetka.'; end if;
  insert into app.slots(team, dow, from_t, to_t, place, valid_from, planned) values (v_team, v_dow, v_from, v_to, app.clean(p_m->>'place', 80), v_since, coalesce((p_m->>'planned')::boolean, false));
  perform app.log_it(s, 'Nov redni termin', v_team || ': ' || (app.days())[v_dow + 1] || ' ' || app.hh(v_from) || '–' || app.hh(v_to) || ' od ' || app.dd(v_since));
  return true;
end $fn$;

-- ---------- odsotnosti ----------
create or replace function public.api_add_absences(p_token text, p_m jsonb)
returns integer language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.sess(p_token); pl app.players := app.need_player(p_token, coalesce(p_m->>'pid', '')); v_reason text := p_m->>'reason'; v_note text := app.clean(p_m->>'note', 200);
        r jsonb; v_a date; v_b date; v_n int := 0;
begin
  if v_reason is null or not (v_reason = any(app.abs_reasons())) then raise exception 'Neveljavna vrednost: %', coalesce(v_reason, ''); end if;
  if jsonb_typeof(p_m->'ranges') <> 'array' or jsonb_array_length(p_m->'ranges') = 0 or jsonb_array_length(p_m->'ranges') > 80 then
    raise exception 'Vpiši datum ali obdobje (največ 80 obdobij naenkrat).';
  end if;
  for r in select * from jsonb_array_elements(p_m->'ranges') loop
    v_a := app.chk_date(r->>'from'); v_b := app.chk_date(coalesce(nullif(r->>'to', ''), r->>'from'));
    if v_b < v_a then raise exception 'Datum »do« mora biti za datumom »od«.'; end if;
    if v_b - v_a > 366 then raise exception 'Obdobje je predolgo.'; end if;
    insert into app.absences(player_id, from_d, to_d, reason, note, who) values (pl.id, v_a, v_b, v_reason, v_note, s.name);
    v_n := v_n + 1;
  end loop;
  perform app.log_it(s, 'Dodana odsotnost', pl.name || ' · ' || v_reason || ' · ' || v_n || ' obdobij');
  return v_n;
end $fn$;

create or replace function public.api_update_absence(p_token text, p_row text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.sess(p_token); r app.absences; pl app.players; v_reason text := p_m->>'reason';
        v_a date := app.chk_date(p_m->>'from'); v_b date := app.chk_date(coalesce(nullif(p_m->>'to', ''), p_m->>'from'));
begin
  select * into r from app.absences where id = p_row::bigint;
  if not found then raise exception 'Odsotnosti ni mogoče najti. Osveži stran.'; end if;
  perform app.need_player(p_token, r.player_id);
  pl := app.need_player(p_token, coalesce(p_m->>'pid', ''));
  if v_reason is null or not (v_reason = any(app.abs_reasons())) then raise exception 'Neveljavna vrednost: %', coalesce(v_reason, ''); end if;
  if v_b < v_a then raise exception 'Datum »do« mora biti za datumom »od«.'; end if;
  update app.absences set player_id = pl.id, from_d = v_a, to_d = v_b, reason = v_reason, note = app.clean(p_m->>'note', 200), who = s.name, at = now() where id = r.id;
  perform app.log_it(s, 'Urejena odsotnost', pl.name || ' · ' || v_reason || ' · ' || app.dd(v_a));
  return true;
end $fn$;

create or replace function public.api_delete_absence(p_token text, p_row text)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.sess(p_token); r app.absences; pl app.players;
begin
  select * into r from app.absences where id = p_row::bigint;
  if not found then raise exception 'Odsotnosti ni mogoče najti. Osveži stran.'; end if;
  pl := app.need_player(p_token, r.player_id);
  delete from app.absences where id = r.id;
  perform app.log_it(s, 'Izbrisana odsotnost', pl.name || ' · ' || r.reason || ' · ' || app.dd(r.from_d));
  return true;
end $fn$;

-- ---------- individualni treningi ----------
create or replace function public.api_add_individual(p_token text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.sess(p_token); pl app.players := app.need_player(p_token, coalesce(p_m->>'pid', ''));
        v_d date := app.chk_date(p_m->>'date'); v_from time := app.chk_time(p_m->>'from'); v_to time := app.chk_time(p_m->>'to');
begin
  if v_from >= v_to then raise exception 'Konec mora biti poznejši od začetka.'; end if;
  insert into app.indiv(player_id, d, from_t, to_t, note, who) values (pl.id, v_d, v_from, v_to, app.clean(p_m->>'note', 200), s.name);
  perform app.log_it(s, 'Dodan individualni trening', pl.name || ' · ' || app.dd(v_d) || ' ' || app.hh(v_from) || '–' || app.hh(v_to));
  return true;
end $fn$;

create or replace function public.api_update_individual(p_token text, p_row text, p_m jsonb)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.sess(p_token); r app.indiv; pl app.players;
        v_d date := app.chk_date(p_m->>'date'); v_from time := app.chk_time(p_m->>'from'); v_to time := app.chk_time(p_m->>'to');
begin
  select * into r from app.indiv where id = p_row::bigint;
  if not found then raise exception 'Treninga ni mogoče najti. Osveži stran.'; end if;
  perform app.need_player(p_token, r.player_id);
  pl := app.need_player(p_token, coalesce(p_m->>'pid', ''));
  if v_from >= v_to then raise exception 'Konec mora biti poznejši od začetka.'; end if;
  update app.indiv set player_id = pl.id, d = v_d, from_t = v_from, to_t = v_to, note = app.clean(p_m->>'note', 200), who = s.name, at = now() where id = r.id;
  perform app.log_it(s, 'Urejen individualni trening', pl.name || ' · ' || app.dd(v_d) || ' ' || app.hh(v_from) || '–' || app.hh(v_to));
  return true;
end $fn$;

create or replace function public.api_delete_individual(p_token text, p_row text)
returns boolean language plpgsql security definer set search_path = app, public, extensions as $fn$
declare s app.tokens := app.sess(p_token); r app.indiv; pl app.players;
begin
  select * into r from app.indiv where id = p_row::bigint;
  if not found then raise exception 'Treninga ni mogoče najti. Osveži stran.'; end if;
  pl := app.need_player(p_token, r.player_id);
  delete from app.indiv where id = r.id;
  perform app.log_it(s, 'Izbrisan individualni trening', pl.name || ' · ' || app.dd(r.d) || ' ' || app.hh(r.from_t) || '–' || app.hh(r.to_t));
  return true;
end $fn$;

-- ---------- dovoljenja: anonimni odjemalec sme klicati samo api_* ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'api\_%' loop
    execute format('revoke all on function %s from public', f.sig);
    execute format('grant execute on function %s to anon, authenticated', f.sig);
  end loop;
end $$;
