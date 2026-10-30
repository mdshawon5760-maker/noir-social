# NOIR — Social

A dark, modern social media starter for sharing photos and videos and connecting with friends.

## Supabase setup

1. Open your Supabase project dashboard.
2. Open **SQL Editor** and create a new query.
3. Copy the complete contents of [supabase-schema.sql](./supabase-schema.sql) into the query and run it.
4. In **Project Settings → API**, confirm the Project URL and publishable key match the values in `index.html`.
5. Keep only the browser-safe publishable (or legacy anon) key in `index.html`. Never put a service-role or secret key in frontend code.
6. In **Authentication → URL Configuration**, add your deployed site URL to the allowed redirect/site URLs as appropriate.
7. Deploy the repository using your hosting provider.

The SQL creates the profile, post, like, comment, and follow tables; row-level security policies; a profile-on-signup trigger; and the public `post-media` Storage bucket with per-user upload restrictions.

## Features

- Email/password sign-up and login
- Feed, explore search, profiles, follows
- Photo/video uploads, likes, comments, and post sharing
- Responsive mobile layout

## Notes

- Email confirmation may need to be completed before a new account can log in, depending on your Supabase Auth settings.
- Uploaded media is publicly viewable because the app uses public media URLs. Do not upload private or sensitive images.
- This is a starter project. Review security and moderation requirements before inviting other people to use it.
