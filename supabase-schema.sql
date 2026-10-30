-- NOIR Social: Supabase database setup
-- Run this whole file in Supabase Dashboard > SQL Editor.
-- Use only the Supabase publishable/anon key in browser code.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_.]{3,24}$'),
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower_idx on public.profiles (lower(username));

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  caption text not null default '' check (char_length(caption) <= 2200),
  media_path text not null,
  media_type text not null check (media_type in ('image','video')),
  created_at timestamptz not null default now()
);
create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_user_id_idx on public.posts (user_id);

create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id,user_id)
);
create index if not exists likes_user_id_idx on public.likes (user_id);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500 and char_length(trim(body)) > 0),
  created_at timestamptz not null default now()
);
create index if not exists comments_post_created_idx on public.comments (post_id,created_at);

create table if not exists public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id,following_id),
  check (follower_id <> following_id)
);
create index if not exists follows_following_id_idx on public.follows (following_id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  handle text;
begin
  handle := lower(coalesce(nullif(new.raw_user_meta_data ->> 'username',''), split_part(coalesce(new.email,''),'@',1), 'member'));
  handle := regexp_replace(handle, '[^a-z0-9_.]', '', 'g');
  if char_length(handle) < 3 then handle := 'user_' || left(replace(new.id::text,'-',''),8); end if;
  handle := left(handle,24);
  if exists (select 1 from public.profiles p where p.username = handle) then
    handle := left(handle,15) || '_' || left(replace(new.id::text,'-',''),8);
  end if;
  insert into public.profiles (id,username) values (new.id,handle)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.follows enable row level security;

drop policy if exists "Signed-in users can read profiles" on public.profiles;
create policy "Signed-in users can read profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "Signed-in users can read posts" on public.posts;
create policy "Signed-in users can read posts" on public.posts for select to authenticated using (true);
drop policy if exists "Users can create their own posts" on public.posts;
create policy "Users can create their own posts" on public.posts for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can update their own posts" on public.posts;
create policy "Users can update their own posts" on public.posts for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users can delete their own posts" on public.posts;
create policy "Users can delete their own posts" on public.posts for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Signed-in users can read likes" on public.likes;
create policy "Signed-in users can read likes" on public.likes for select to authenticated using (true);
drop policy if exists "Users can add their own likes" on public.likes;
create policy "Users can add their own likes" on public.likes for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can remove their own likes" on public.likes;
create policy "Users can remove their own likes" on public.likes for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Signed-in users can read comments" on public.comments;
create policy "Signed-in users can read comments" on public.comments for select to authenticated using (true);
drop policy if exists "Users can add their own comments" on public.comments;
create policy "Users can add their own comments" on public.comments for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can delete their own comments" on public.comments;
create policy "Users can delete their own comments" on public.comments for delete to authenticated using (auth.uid() = user_id);

drop policy if exists "Signed-in users can read follows" on public.follows;
create policy "Signed-in users can read follows" on public.follows for select to authenticated using (true);
drop policy if exists "Users can follow from their own account" on public.follows;
create policy "Users can follow from their own account" on public.follows for insert to authenticated with check (auth.uid() = follower_id and follower_id <> following_id);
drop policy if exists "Users can unfollow from their own account" on public.follows;
create policy "Users can unfollow from their own account" on public.follows for delete to authenticated using (auth.uid() = follower_id);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('post-media','post-media',true,52428800,
  array['image/jpeg','image/png','image/webp','image/gif','image/avif','video/mp4','video/webm','video/quicktime'])
on conflict (id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Anyone can view NOIR post media" on storage.objects;
create policy "Anyone can view NOIR post media" on storage.objects for select using (bucket_id='post-media');
drop policy if exists "Users can upload to their own NOIR folder" on storage.objects;
create policy "Users can upload to their own NOIR folder" on storage.objects for insert to authenticated with check (bucket_id='post-media' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Users can delete from their own NOIR folder" on storage.objects;
create policy "Users can delete from their own NOIR folder" on storage.objects for delete to authenticated using (bucket_id='post-media' and (storage.foldername(name))[1]=auth.uid()::text);
